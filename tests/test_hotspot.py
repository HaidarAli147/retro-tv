"""Offline checks for the Wi-Fi hotspot backup: python3 -m unittest tests.test_hotspot -v

No Wi-Fi, NetworkManager, display or root needed: nmcli is replaced by a fake.
"""
import json
import os
import pathlib
import socket
import stat
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi"))
import hotspot as hs
import remote_server as rs
import tv

HOME_WIFI = "wlan0:wifi:connected:Home Wi-Fi\n" "eth0:ethernet:unavailable:\n" "lo:loopback:unmanaged:\n"
NO_NETWORK = "wlan0:wifi:disconnected:\n" "eth0:ethernet:unavailable:\n" "lo:loopback:unmanaged:\n"
HOTSPOT_UP = "wlan0:wifi:connected:RetroTV-Hotspot\n" "eth0:ethernet:unavailable:\n"
CABLE = "wlan0:wifi:disconnected:\n" "eth0:ethernet:connected:Wired connection 1\n"


class FakeNmcli:
    """Answers nmcli calls from a table and records every call."""

    def __init__(self, devices=NO_NETWORK, ap="yes", fail=()):
        self.devices_out, self.ap, self.fail, self.calls = devices, ap, set(fail), []

    def __call__(self, args, timeout=20):
        args = list(args)
        self.calls.append(args)
        for word in self.fail:
            if word in args:
                return 1, "", "Error: simulated failure of %s" % word
        if args[:3] == ["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION"]:
            return 0, self.devices_out, ""
        if "WIFI-PROPERTIES.AP" in args:
            return 0, self.ap + "\n", ""
        if "IP4.ADDRESS" in args:
            return 0, "10.42.0.1/24\n", ""
        if args[:3] == ["-t", "-f", "NAME"]:
            return 0, "Wired connection 1\n", ""
        return 0, "", ""


class ParsingTests(unittest.TestCase):
    def test_terse_fields_and_escaped_colons(self):
        self.assertEqual(hs.split_terse("wlan0:wifi:connected:Home"), ["wlan0", "wifi", "connected", "Home"])
        self.assertEqual(hs.split_terse(r"wlan0:wifi:connected:My\:Net"), ["wlan0", "wifi", "connected", "My:Net"])
        self.assertEqual(hs.split_terse(r"a\\b:c"), ["a\\b", "c"])
        self.assertEqual(hs.split_terse("eth0:ethernet:unavailable:"), ["eth0", "ethernet", "unavailable", ""])

    def test_network_detection(self):
        for out, network, active in ((HOME_WIFI, True, False), (NO_NETWORK, False, False),
                                     (CABLE, True, False), (HOTSPOT_UP, False, True)):
            with patch.object(hs, "_nmcli", FakeNmcli(out)):
                rows = hs.devices()
                self.assertEqual(hs.has_network(rows), network, out)
                self.assertEqual(hs.is_active(rows), active, out)

    def test_a_cable_managed_by_something_else_still_counts(self):
        out = "eth0:ethernet:connected (externally):Wired\nwlan0:wifi:disconnected:\n"
        with patch.object(hs, "_nmcli", FakeNmcli(out)):
            self.assertTrue(hs.has_network())

    def test_our_own_hotspot_never_counts_as_a_network(self):
        with patch.object(hs, "_nmcli", FakeNmcli(HOTSPOT_UP)):
            self.assertFalse(hs.has_network())

    def test_wifi_adapter_and_ap_support(self):
        with patch.object(hs, "_nmcli", FakeNmcli(NO_NETWORK)):
            self.assertEqual(hs.wifi_device(), {"device": "wlan0", "state": "disconnected"})
            self.assertTrue(hs.supports_ap("wlan0"))
        with patch.object(hs, "_nmcli", FakeNmcli(NO_NETWORK, ap="no")):
            self.assertFalse(hs.supports_ap("wlan0"))
        with patch.object(hs, "_nmcli", FakeNmcli(NO_NETWORK, ap="weird")):
            self.assertIsNone(hs.supports_ap("wlan0"))
        with patch.object(hs, "_nmcli", FakeNmcli("eth0:ethernet:connected:x\n")):
            self.assertIsNone(hs.wifi_device())

    def test_missing_nmcli_is_not_a_crash(self):
        with patch.object(hs.subprocess, "run", side_effect=FileNotFoundError):
            self.assertEqual(hs._nmcli(["device"])[0], 127)
            self.assertEqual(hs.devices(), [])
            self.assertFalse(hs.has_network())

    def test_address(self):
        with patch.object(hs, "_nmcli", FakeNmcli()):
            self.assertEqual(hs.address("wlan0"), "10.42.0.1")


class CredentialTests(unittest.TestCase):
    def test_format_and_no_confusing_letters(self):
        for _ in range(50):
            c = hs.new_credentials()
            self.assertRegex(c["ssid"], r"^RetroTV-[A-Z2-9]{4}$")
            self.assertRegex(c["password"], r"^[A-Z2-9]{10}$")
            self.assertFalse(set("0O1IL") & set(c["password"] + c["ssid"][8:]))

    def test_created_once_kept_and_private(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "sub", "hotspot.json")
            first = hs.load_credentials(path)
            self.assertEqual(hs.load_credentials(path), first)
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)

    def test_damaged_file_is_replaced(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "hotspot.json")
            for bad in ("not json", json.dumps({"ssid": "x", "password": "y"}), json.dumps([1, 2])):
                pathlib.Path(path).write_text(bad)
                c = hs.load_credentials(path)
                self.assertRegex(c["ssid"], r"^RetroTV-")
                self.assertEqual(hs.load_credentials(path), c)

    def test_unwritable_location_still_gives_credentials(self):
        c = hs.load_credentials("/proc/definitely/not/writable/hotspot.json")
        self.assertRegex(c["password"], r"^[A-Z2-9]{10}$")

    def test_wifi_qr_text(self):
        self.assertEqual(hs.wifi_qr_text("RetroTV-AB23", "PASS1234XY"),
                         "WIFI:T:WPA;S:RetroTV-AB23;P:PASS1234XY;;")
        self.assertEqual(hs.wifi_qr_text("a;b", 'p:"q\\'), 'WIFI:T:WPA;S:a\\;b;P:p\\:\\"q\\\\;;')


class StartStopTests(unittest.TestCase):
    CREDS = {"ssid": "RetroTV-AB23", "password": "PASS1234XY"}

    def test_start_builds_a_protected_shared_access_point(self):
        fake = FakeNmcli()
        with patch.object(hs, "_nmcli", fake):
            ok, message = hs.start(self.CREDS)
        self.assertTrue(ok)
        self.assertEqual(message, "RetroTV-AB23")
        add = next(c for c in fake.calls if c[:2] == ["connection", "add"])
        pairs = dict(zip(add[2::2], add[3::2]))
        self.assertEqual(pairs["ifname"], "wlan0")
        self.assertEqual(pairs["802-11-wireless.mode"], "ap")
        self.assertEqual(pairs["ipv4.method"], "shared")
        self.assertEqual(pairs["wifi-sec.key-mgmt"], "wpa-psk")        # never an open network
        self.assertEqual(pairs["wifi-sec.psk"], "PASS1234XY")
        self.assertEqual(pairs["autoconnect"], "no")                    # must not start at boot by itself
        self.assertEqual(fake.calls[-1], ["connection", "up", hs.CONNECTION])
        self.assertLess(fake.calls.index(["connection", "delete", hs.CONNECTION]),
                        fake.calls.index(add))                           # stale profile removed first

    def test_each_failure_has_a_plain_message_and_leaves_nothing_behind(self):
        with patch.object(hs, "_nmcli", FakeNmcli("eth0:ethernet:connected:x\n")):
            self.assertEqual(hs.start(self.CREDS), (False, "NO WI-FI ADAPTER FOUND"))
        with patch.object(hs, "_nmcli", FakeNmcli("wlan0:wifi:unavailable:\n")):
            ok, message = hs.start(self.CREDS)
            self.assertFalse(ok)
            self.assertIn("COUNTRY", message)
        with patch.object(hs, "_nmcli", FakeNmcli(ap="no")):
            self.assertEqual(hs.start(self.CREDS), (False, "THIS WI-FI ADAPTER CANNOT MAKE A HOTSPOT"))
        fake = FakeNmcli(fail=("add",))
        with patch.object(hs, "_nmcli", fake):
            ok, message = hs.start(self.CREDS)
        self.assertFalse(ok)
        self.assertTrue(message.startswith("HOTSPOT SETUP FAILED"))
        fake = FakeNmcli(fail=("up",))
        with patch.object(hs, "_nmcli", fake):
            ok, message = hs.start(self.CREDS)
        self.assertFalse(ok)
        self.assertTrue(message.startswith("HOTSPOT DID NOT START"))
        self.assertEqual(fake.calls[-1], ["connection", "delete", hs.CONNECTION])

    def test_stop_does_nothing_when_there_is_nothing_to_stop(self):
        fake = FakeNmcli(HOME_WIFI)
        with patch.object(hs, "_nmcli", fake):
            self.assertTrue(hs.stop())
        self.assertFalse(any(c[:2] in (["connection", "down"], ["connection", "delete"]) for c in fake.calls))

    def test_stop_switches_off_and_forgets_the_profile(self):
        class Up(FakeNmcli):
            def __call__(self, args, timeout=20):
                out = super().__call__(args, timeout)
                if list(args)[:2] == ["connection", "down"]:
                    self.devices_out = NO_NETWORK
                return out
        fake = Up(HOTSPOT_UP)
        with patch.object(hs, "_nmcli", fake):
            self.assertTrue(hs.stop())
        self.assertIn(["connection", "down", hs.CONNECTION], fake.calls)
        self.assertIn(["connection", "delete", hs.CONNECTION], fake.calls)


class PolicyTests(unittest.TestCase):
    def test_auto_waits_for_the_grace_period(self):
        p = hs.Policy(grace=30, retry=120)
        self.assertIsNone(p.decide(0, "auto", network=False, active=False))      # first sighting
        self.assertIsNone(p.decide(29, "auto", network=False, active=False))
        self.assertEqual(p.decide(30, "auto", network=False, active=False), "start")

    def test_a_returning_network_cancels_the_wait(self):
        p = hs.Policy(grace=30)
        p.decide(0, "auto", False, False)
        p.decide(20, "auto", True, False)                                        # Wi-Fi came back
        self.assertIsNone(p.decide(40, "auto", False, False))                    # clock restarted
        self.assertEqual(p.decide(70, "auto", False, False), "start")

    def test_auto_stops_when_a_cable_appears_but_not_otherwise(self):
        p = hs.Policy()
        self.assertEqual(p.decide(0, "auto", network=True, active=True), "stop")
        self.assertIsNone(p.decide(1, "auto", network=False, active=True))

    def test_settings_screen_pauses_auto_and_restarts_the_wait(self):
        p = hs.Policy(grace=30)
        p.decide(0, "auto", False, False)
        self.assertIsNone(p.decide(100, "auto", False, False, suppress=True))
        self.assertIsNone(p.decide(101, "auto", False, False))                   # wait starts over
        self.assertIsNone(p.decide(130, "auto", False, False))
        self.assertEqual(p.decide(131, "auto", False, False), "start")

    def test_failure_backs_off(self):
        p = hs.Policy(grace=0, retry=120)
        p.decide(0, "auto", False, False)
        self.assertEqual(p.decide(1, "auto", False, False), "start")
        p.failed(1)
        self.assertIsNone(p.decide(60, "auto", False, False))
        self.assertEqual(p.decide(121, "auto", False, False), "start")

    def test_on_and_off(self):
        p = hs.Policy()
        self.assertEqual(p.decide(0, "on", network=True, active=False), "start")
        self.assertIsNone(p.decide(1, "on", network=True, active=True))
        self.assertEqual(p.decide(2, "off", network=False, active=True), "stop")
        self.assertIsNone(p.decide(3, "off", network=False, active=False))

    def test_on_waits_in_settings_unless_just_chosen(self):
        p = hs.Policy()
        self.assertIsNone(p.decide(0, "on", True, False, suppress=True))
        self.assertEqual(p.decide(1, "on", True, False, suppress=True, force=True), "start")

    def test_force_ignores_the_retry_wait(self):
        p = hs.Policy(retry=120)
        p.failed(0)
        self.assertIsNone(p.decide(10, "on", True, False))
        self.assertEqual(p.decide(10, "on", True, False, force=True), "start")

    def test_unknown_mode_means_auto(self):
        self.assertEqual(hs.clean_mode("nonsense"), "auto")
        self.assertEqual(hs.clean_mode(None), "auto")


class RemoteAddressTests(unittest.TestCase):
    def _run(self, text):
        return SimpleNamespace(stdout=text, returncode=0)

    def test_no_default_route_falls_back_to_the_interface_address(self):
        class NoRoute:
            def connect(self, *_): raise OSError("Network is unreachable")
            def close(self): pass
        ip_out = "3: wlan0    inet 10.42.0.1/24 brd 10.42.0.255 scope global noprefixroute wlan0\n"
        with patch.object(rs.socket, "socket", return_value=NoRoute()), \
                patch.object(rs.subprocess, "run", return_value=self._run(ip_out)):
            self.assertEqual(rs.lan_ip(), "10.42.0.1")

    def test_loopback_answer_is_not_trusted(self):
        class Loop:
            def connect(self, *_): pass
            def getsockname(self): return ("127.0.0.1", 0)
            def close(self): pass
        ip_out = "2: eth0    inet 192.168.1.50/24 brd 192.168.1.255 scope global eth0\n"
        with patch.object(rs.socket, "socket", return_value=Loop()), \
                patch.object(rs.subprocess, "run", return_value=self._run(ip_out)):
            self.assertEqual(rs.lan_ip(), "192.168.1.50")

    def test_normal_route_is_unchanged(self):
        class Good:
            def connect(self, *_): pass
            def getsockname(self): return ("192.168.100.209", 0)
            def close(self): pass
        with patch.object(rs.socket, "socket", return_value=Good()):
            self.assertEqual(rs.lan_ip(), "192.168.100.209")

    def test_nothing_found_is_localhost_and_public_addresses_are_skipped(self):
        class NoRoute:
            def connect(self, *_): raise OSError
            def close(self): pass
        with patch.object(rs.socket, "socket", return_value=NoRoute()), \
                patch.object(rs.subprocess, "run", side_effect=FileNotFoundError):
            self.assertEqual(rs.lan_ip(), "127.0.0.1")
        with patch.object(rs.socket, "socket", return_value=NoRoute()), \
                patch.object(rs.subprocess, "run",
                             return_value=self._run("2: eth0 inet 8.8.4.4/24 scope global eth0\n")):
            self.assertEqual(rs.lan_ip(), "127.0.0.1")

    def test_hotspot_address_wins_in_the_qr_link(self):
        server = rs.RemoteServer(input_backend=SimpleNamespace(available=False))
        server.port = 8080
        server.host_override = "10.42.0.1"
        self.assertEqual(server.url(), "http://10.42.0.1:8080/")
        self.assertTrue(server.qr_link().startswith("http://10.42.0.1:8080/#code="))

    def test_hotspot_clients_are_accepted_by_the_server(self):
        self.assertTrue(rs.is_local_client("10.42.0.37"))
        self.assertTrue(rs.is_local_host_header("10.42.0.1:8080"))


class WindowLogicTests(unittest.TestCase):
    """The TVWindow methods run on a stand-in object: no display needed."""

    def make(self, mode="auto"):
        events = []
        win = SimpleNamespace(
            _closed=False, _hs_mode=mode, _hs_active=False, _hs_force=False, _hs_message="x",
            _hs_busy=False, _hs_policy=hs.Policy(grace=0), _prefs={}, screen="HOME",
            remote=SimpleNamespace(host_override="old"),
            hs_label=SimpleNamespace(set_text=lambda t: events.append(("label", t))),
            _save_prefs=lambda: events.append(("saved",)),
            _hotspot_tick=lambda: events.append(("tick",)),
            _hotspot_run=lambda start: events.append(("run", start)),
            _hotspot_changed=lambda: events.append(("changed",)),
        )
        win._show_hotspot_mode = lambda: tv.TVWindow._show_hotspot_mode(win)
        return win, events

    def test_cycling_saves_forces_and_clears_old_errors(self):
        win, events = self.make("auto")
        tv.TVWindow.cycle_hotspot_mode(win, 1)
        self.assertEqual(win._hs_mode, "on")
        self.assertEqual(win._prefs["hotspot"], "on")
        self.assertTrue(win._hs_force)
        self.assertEqual(win._hs_message, "")
        self.assertIn(("saved",), events)
        self.assertIn(("tick",), events)
        tv.TVWindow.cycle_hotspot_mode(win, 1)
        tv.TVWindow.cycle_hotspot_mode(win, 1)
        self.assertEqual(win._hs_mode, "auto")                      # wraps around

    def test_decision_starts_after_grace_and_stops_with_a_cable(self):
        win, events = self.make("auto")
        done = SimpleNamespace(result=lambda: (False, False, True))
        tv.TVWindow._hotspot_decide(win, done)                       # first sighting
        tv.TVWindow._hotspot_decide(win, done)                       # grace is 0
        self.assertIn(("run", True), events)
        win, events = self.make("auto")
        win._hs_active = True
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (True, True, True)))
        self.assertIn(("run", False), events)

    def test_settings_screen_blocks_an_automatic_start(self):
        win, events = self.make("auto")
        win.screen = "SETTINGS"
        done = SimpleNamespace(result=lambda: (False, False, True))
        for _ in range(3):
            tv.TVWindow._hotspot_decide(win, done)
        self.assertNotIn(("run", True), events)

    def test_someone_else_switching_it_off_clears_the_address(self):
        win, events = self.make("auto")
        win._hs_active = True
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (False, False, True)))
        self.assertIsNone(win.remote.host_override)
        self.assertIn(("changed",), events)

    def test_observation_error_does_not_wedge_the_loop(self):
        win, _ = self.make()
        def boom(): raise RuntimeError("nmcli died")
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=boom))
        self.assertFalse(win._hs_busy)

    def test_no_answer_from_networkmanager_means_do_nothing(self):
        win, events = self.make("auto")
        for _ in range(5):
            tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (False, False, False)))
        self.assertNotIn(("run", True), events)
        self.assertFalse(win._hs_busy)
        self.assertEqual(win._hs_message, "x")                       # and no new error shown

    def test_label_when_unavailable(self):
        win, events = self.make()
        win.remote = None
        tv.TVWindow._show_hotspot_mode(win)
        self.assertEqual(events[-1], ("label", " NOT AVAILABLE "))

    def test_wifi_jobs_give_the_radio_back_first(self):
        calls = []
        class Pool:
            def submit(self, fn):
                calls.append(("worker", fn()))
                return SimpleNamespace(add_done_callback=lambda cb: None)
        win = SimpleNamespace(_closed=False, _hs_active=True, _wifi_workers=Pool())
        with patch.object(hs, "stop", lambda: calls.append(("hotspot stop",))), \
                patch.object(tv.subprocess, "run", return_value=SimpleNamespace(returncode=0)):
            tv.TVWindow._wifi_job(win, ["nmcli", "device", "wifi", "list"], lambda r: None)
        self.assertEqual(calls[0], ("hotspot stop",))
        self.assertFalse(win._hs_active)


if __name__ == "__main__":
    unittest.main()
