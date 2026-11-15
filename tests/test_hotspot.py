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
BOTH_READY = "wlp3s0:wifi:connected:Home Wi-Fi\n" "ap0:wifi:disconnected:\n" "lo:loopback:unmanaged:\n"
BOTH_RUNNING = "wlp3s0:wifi:connected:Home Wi-Fi\n" "ap0:wifi:connected:RetroTV-Hotspot\n"
AP0_UNMANAGED = "wlp3s0:wifi:connected:Home Wi-Fi\n" "ap0:wifi:unmanaged:\n"
CABLE = "wlan0:wifi:disconnected:\n" "eth0:ethernet:connected:Wired connection 1\n"


class FakeNmcli:
    """Answers nmcli calls from a table and records every call."""

    def __init__(self, devices=NO_NETWORK, ap="yes", fail=(), wifi_list="*:6:2437 MHz\n :11:2462 MHz\n"):
        self.devices_out, self.ap, self.fail, self.calls = devices, ap, set(fail), []
        self.wifi_list = wifi_list

    def __call__(self, args, timeout=20):
        args = list(args)
        self.calls.append(args)
        for word in self.fail:
            if word in args:
                return 1, "", "Error: simulated failure of %s" % word
        if args[:3] == ["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION"]:
            return 0, self.devices_out, ""
        if args[:3] == ["-t", "-f", "IN-USE,CHAN,FREQ"]:
            return 0, self.wifi_list, ""
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


class ConcurrentTests(unittest.TestCase):
    CREDS = {"ssid": "RetroTV-AB23", "password": "PASS1234XY"}

    def test_ap0_is_found_and_the_normal_adapter_is_not_confused_with_it(self):
        with patch.object(hs, "_nmcli", FakeNmcli(BOTH_READY)):
            rows = hs.devices()
            self.assertEqual(hs.ap_device(rows), "ap0")
            self.assertEqual(hs.wifi_device(rows)["device"], "wlp3s0")        # ap0 is never the main adapter
            self.assertEqual(hs.station(rows), {"device": "wlp3s0", "connection": "Home Wi-Fi"})
            self.assertIsNone(hs.active_device(rows))
        with patch.object(hs, "_nmcli", FakeNmcli(AP0_UNMANAGED)):
            self.assertIsNone(hs.ap_device())                                   # unusable: fall back to one radio
        with patch.object(hs, "_nmcli", FakeNmcli(HOME_WIFI)):
            self.assertIsNone(hs.ap_device())

    def test_running_on_ap0_counts_as_both_and_the_home_wifi_still_counts_as_network(self):
        with patch.object(hs, "_nmcli", FakeNmcli(BOTH_RUNNING)):
            rows = hs.devices()
            self.assertEqual(hs.active_device(rows), "ap0")
            self.assertTrue(hs.is_active(rows))
            self.assertTrue(hs.has_network(rows))
            self.assertEqual(hs.station(rows)["device"], "wlp3s0")

    def test_channel_of_the_normal_connection(self):
        with patch.object(hs, "_nmcli", FakeNmcli(wifi_list="*:6:2437 MHz\n :11:2462 MHz\n")):
            self.assertEqual(hs.sta_channel("wlp3s0"), ("bg", 6))
        with patch.object(hs, "_nmcli", FakeNmcli(wifi_list=" :1:2412 MHz\n*:36:5180 MHz\n")):
            self.assertEqual(hs.sta_channel("wlp3s0"), ("a", 36))
        with patch.object(hs, "_nmcli", FakeNmcli(wifi_list=" :1:2412 MHz\n")):
            self.assertIsNone(hs.sta_channel("wlp3s0"))                         # not connected
        with patch.object(hs, "_nmcli", FakeNmcli(wifi_list="*:oops:no\n")):
            self.assertIsNone(hs.sta_channel("wlp3s0"))

    def test_start_beside_wifi_uses_ap0_and_the_same_channel(self):
        fake = FakeNmcli(BOTH_READY, wifi_list=" :1:2412 MHz\n*:44:5220 MHz\n")
        with patch.object(hs, "_nmcli", fake):
            ok, message = hs.start(self.CREDS)
        self.assertTrue(ok)
        add = next(c for c in fake.calls if c[:2] == ["connection", "add"])
        pairs = dict(zip(add[2::2], add[3::2]))
        self.assertEqual(pairs["ifname"], "ap0")                                # not the adapter that carries the Wi-Fi
        self.assertEqual(pairs["802-11-wireless.band"], "a")
        self.assertEqual(pairs["802-11-wireless.channel"], "44")                # must match the Wi-Fi's channel
        self.assertEqual(pairs["wifi-sec.key-mgmt"], "wpa-psk")
        self.assertNotIn(["connection", "down", "Home Wi-Fi"], fake.calls)      # the normal Wi-Fi is left alone

    def test_start_on_ap0_without_a_connected_wifi_uses_default_band(self):
        fake = FakeNmcli("wlp3s0:wifi:disconnected:\n" "ap0:wifi:disconnected:\n")
        with patch.object(hs, "_nmcli", fake):
            self.assertTrue(hs.start(self.CREDS)[0])
        add = next(c for c in fake.calls if c[:2] == ["connection", "add"])
        pairs = dict(zip(add[2::2], add[3::2]))
        self.assertEqual((pairs["ifname"], pairs["802-11-wireless.band"]), ("ap0", "bg"))
        self.assertNotIn("802-11-wireless.channel", pairs)

    def test_without_ap0_it_is_still_the_single_radio_mode(self):
        fake = FakeNmcli(NO_NETWORK)
        with patch.object(hs, "_nmcli", fake):
            self.assertTrue(hs.start(self.CREDS)[0])
        add = next(c for c in fake.calls if c[:2] == ["connection", "add"])
        self.assertEqual(dict(zip(add[2::2], add[3::2]))["ifname"], "wlan0")

    def test_policy_with_ap0_keeps_the_hotspot_on_whatever_the_network_does(self):
        p = hs.Policy(grace=30)
        self.assertEqual(p.decide(0, "auto", network=True, active=False, concurrent=True), "start")
        self.assertIsNone(p.decide(1, "auto", network=True, active=True, concurrent=True))
        self.assertIsNone(p.decide(2, "auto", network=False, active=True, concurrent=True))   # no stop for a cable either
        self.assertEqual(p.decide(3, "auto", network=True, active=False, suppress=True, concurrent=True), "start")  # Settings need not pause it
        self.assertEqual(p.decide(4, "off", network=True, active=True, concurrent=True), "stop")
        self.assertIsNone(p.decide(5, "off", network=True, active=False, concurrent=True))

    def test_policy_with_ap0_still_backs_off_after_a_failure(self):
        p = hs.Policy(retry=120)
        p.failed(0)
        self.assertIsNone(p.decide(10, "auto", True, False, concurrent=True))
        self.assertEqual(p.decide(130, "auto", True, False, concurrent=True), "start")

    def test_without_ap0_auto_is_unchanged(self):
        p = hs.Policy(grace=30)
        self.assertIsNone(p.decide(0, "auto", network=True, active=False, concurrent=False))
        self.assertEqual(p.decide(1, "auto", network=True, active=True, concurrent=False), "stop")


class DeviceTrackingTests(unittest.TestCase):
    def test_phones_count_while_they_keep_checking_in(self):
        clock = [0.0]
        p = rs.Pairing(code="123456", clock=lambda: clock[0])
        self.assertEqual(p.active(120), 0)
        token = p.pair("10.42.0.5", "123456")
        self.assertEqual(p.active(120), 1)
        clock[0] = 100
        self.assertEqual(p.active(120), 1)
        clock[0] = 130
        self.assertEqual(p.active(120), 0)                                       # quiet for too long
        self.assertTrue(p.valid(token))                                          # the phone is back (heartbeat)
        self.assertEqual(p.active(120), 1)

    def test_wrong_tokens_never_count_and_old_tokens_are_forgotten(self):
        clock = [0.0]
        p = rs.Pairing(code="123456", clock=lambda: clock[0])
        self.assertFalse(p.valid("nonsense"))
        self.assertEqual(p.active(120), 0)
        tokens = [p.pair("10.0.0.%d" % i, "123456") for i in range(rs.MAX_TOKENS + 5)]
        self.assertEqual(p.count(), rs.MAX_TOKENS)
        self.assertEqual(p.active(120), rs.MAX_TOKENS)
        self.assertFalse(p.valid(tokens[0]))                                     # pushed out by newer phones
        self.assertEqual(len(p._seen), rs.MAX_TOKENS)

    def test_server_reports_connected_devices(self):
        server = rs.RemoteServer(input_backend=SimpleNamespace(available=False))
        self.assertEqual(server.connected_devices(), 0)
        server.pairing.pair("10.0.0.2", server.pairing.code)
        self.assertEqual(server.connected_devices(), 1)

    def test_the_phone_page_sends_a_heartbeat(self):
        page = (pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi" / "remote_page.html").read_text()
        self.assertIn("setInterval(heartbeat, 15000)", page)
        self.assertIn("/api/status", page)


class HintTests(unittest.TestCase):
    def test_popup_does_not_reuse_the_bottom_bar_name(self):
        # tv.py already has self.hint = the grey hint bar (a Label). A pop-up stored under
        # that name was silently replaced by it and never appeared.
        src = (pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi" / "tv.py").read_text()
        self.assertIn("self.connect_hint = RemoteHint()", src)
        self.assertNotRegex(src, r"self\.hint\.(show_info|dismiss|destroy)\b")
        self.assertEqual(src.count("self.hint = "), 1)

    def test_when_the_popup_is_wanted(self):
        w = lambda **k: tv.hint_wanted(**{**dict(has_hotspot=True, mode="auto", remote_running=True,
                                                 screen="HOME", connected=0, dismissed=False), **k})
        self.assertTrue(w())
        self.assertTrue(w(mode="on"))
        self.assertTrue(w(screen="LIVE"))
        self.assertFalse(w(mode="off"))                  # the user switched the hotspot feature off
        self.assertFalse(w(screen="REMOTE"))             # that screen already shows everything
        self.assertFalse(w(connected=1))                 # a phone is connected
        self.assertFalse(w(dismissed=True))              # BACK was pressed
        self.assertFalse(w(remote_running=False))
        self.assertFalse(w(has_hotspot=False))

    def make(self):
        shown = []
        class Hint:
            visible = False
            def get_visible(self): return self.visible
            def show_info(self, wifi, address, code):
                self.visible = True
                shown.append((tuple(wifi), address, code))
            def dismiss(self): self.visible = False
        win = SimpleNamespace(
            _closed=False, _hs_mode="auto", _hs_active=True, _hint_dismissed=False, _hint_key=None, _hs_known=True,
            _hs_creds={"ssid": "RetroTV-AB23", "password": "PASS1234XY"}, screen="HOME",
            remote=SimpleNamespace(connected_devices=lambda: win.connected, url=lambda: "http://10.42.0.1:8080/",
                                   pairing=SimpleNamespace(code="123456")),
            connect_hint=Hint(), connected=0)
        return win, shown

    def test_popup_shows_name_password_address_and_code(self):
        win, shown = self.make()
        tv.TVWindow._hint_update(win)
        self.assertEqual(shown, [(("JOIN WI-FI:  RetroTV-AB23", "PASSWORD:    PASS1234XY"),
                                  "http://10.42.0.1:8080/", "123456")])
        tv.TVWindow._hint_update(win)
        self.assertEqual(len(shown), 1)                  # no flicker: not re-shown when nothing changed

    def test_popup_without_a_hotspot_still_gives_address_and_code(self):
        win, shown = self.make()
        win._hs_active = False
        tv.TVWindow._hint_update(win)
        self.assertEqual(shown[0][0], ())
        self.assertEqual(shown[0][2], "123456")

    def test_no_popup_where_networkmanager_is_missing(self):
        win, shown = self.make()
        win._hs_known = False                              # nmcli never answered: the hotspot cannot work here
        tv.TVWindow._hint_update(win)
        self.assertEqual(shown, [])

    def test_decide_remembers_whether_networkmanager_answers(self):
        events = []
        win = SimpleNamespace(_closed=False, _hs_busy=True, _hs_known=True, _hs_active=False, _hs_mode="auto")
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (False, False, False, False, None)))
        self.assertFalse(win._hs_known)

    def test_popup_follows_a_changed_code(self):
        win, shown = self.make()
        tv.TVWindow._hint_update(win)
        win.remote.pairing.code = "654321"
        tv.TVWindow._hint_update(win)
        self.assertEqual([s[2] for s in shown], ["123456", "654321"])

    def test_phone_connecting_hides_it_and_leaving_brings_it_back(self):
        win, shown = self.make()
        tv.TVWindow._hint_update(win)
        self.assertTrue(win.connect_hint.visible)
        win.connected = 1
        tv.TVWindow._hint_update(win)
        self.assertFalse(win.connect_hint.visible)
        win.connected = 0                                 # phone went away
        tv.TVWindow._hint_update(win)
        self.assertTrue(win.connect_hint.visible)

    def test_back_hides_it_until_a_phone_has_connected(self):
        win, shown = self.make()
        tv.TVWindow._hint_update(win)
        win._hint_dismissed = True                        # what the BACK key does
        win.connect_hint.dismiss()
        for _ in range(3):
            tv.TVWindow._hint_update(win)
        self.assertFalse(win.connect_hint.visible)
        win.connected = 1
        tv.TVWindow._hint_update(win)
        win.connected = 0
        tv.TVWindow._hint_update(win)
        self.assertTrue(win.connect_hint.visible)

    def test_opening_the_remote_screen_counts_as_seen(self):
        win, shown = self.make()
        win.screen = "REMOTE"
        tv.TVWindow._hint_update(win)
        self.assertFalse(win.connect_hint.visible)
        win.screen = "HOME"                               # they pressed BACK to leave it
        tv.TVWindow._hint_update(win)
        self.assertFalse(win.connect_hint.visible)


class WindowLogicTests(unittest.TestCase):
    """The TVWindow methods run on a stand-in object: no display needed."""

    def make(self, mode="auto"):
        events = []
        win = SimpleNamespace(
            _closed=False, _hs_mode=mode, _hs_active=False, _hs_force=False, _hs_message="x",
            _hs_busy=False, _hs_policy=hs.Policy(grace=0), _prefs={}, screen="HOME",
            _hs_network=False, _hs_concurrent=False, _hs_concurrent_ok=False, _hint_dismissed=True, _hs_known=False,
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
        done = SimpleNamespace(result=lambda: (False, False, True, False, None))
        tv.TVWindow._hotspot_decide(win, done)                       # first sighting
        tv.TVWindow._hotspot_decide(win, done)                       # grace is 0
        self.assertIn(("run", True), events)
        win, events = self.make("auto")
        win._hs_active = True
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (True, True, True, False, "wlan0")))
        self.assertIn(("run", False), events)

    def test_settings_screen_blocks_an_automatic_start(self):
        win, events = self.make("auto")
        win.screen = "SETTINGS"
        done = SimpleNamespace(result=lambda: (False, False, True, False, None))
        for _ in range(3):
            tv.TVWindow._hotspot_decide(win, done)
        self.assertNotIn(("run", True), events)

    def test_someone_else_switching_it_off_clears_the_address(self):
        win, events = self.make("auto")
        win._hs_active = True
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (False, False, True, False, None)))
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
            tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (False, False, False, False, None)))
        self.assertNotIn(("run", True), events)
        self.assertFalse(win._hs_busy)
        self.assertEqual(win._hs_message, "x")                       # and no new error shown

    def test_with_ap0_the_hotspot_starts_even_though_wifi_is_connected(self):
        win, events = self.make("auto")
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (True, False, True, True, None)))
        self.assertIn(("run", True), events)
        self.assertTrue(win._hs_concurrent_ok)
        self.assertTrue(win._hs_network)

    def test_running_on_ap0_is_remembered_as_concurrent(self):
        win, events = self.make("auto")
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (True, True, True, True, "ap0")))
        self.assertTrue(win._hs_concurrent)
        self.assertNotIn(("run", False), events)                       # and it is left running
        tv.TVWindow._hotspot_decide(win, SimpleNamespace(result=lambda: (True, True, True, False, "wlan0")))
        self.assertFalse(win._hs_concurrent)

    def test_label_when_unavailable(self):
        win, events = self.make()
        win.remote = None
        tv.TVWindow._show_hotspot_mode(win)
        self.assertEqual(events[-1], ("label", " NOT AVAILABLE "))

    def test_wifi_jobs_leave_a_hotspot_on_ap0_alone(self):
        calls = []
        class Pool:
            def submit(self, fn):
                calls.append(("worker", fn()))
                return SimpleNamespace(add_done_callback=lambda cb: None)
        win = SimpleNamespace(_closed=False, _hs_active=True, _hs_concurrent=True, _wifi_workers=Pool())
        with patch.object(hs, "stop", lambda: calls.append(("hotspot stop",))), \
                patch.object(tv.subprocess, "run", return_value=SimpleNamespace(returncode=0)):
            tv.TVWindow._wifi_job(win, ["nmcli", "device", "wifi", "list"], lambda r: None)
        self.assertNotIn(("hotspot stop",), calls)
        self.assertTrue(win._hs_active)

    def test_wifi_jobs_give_the_radio_back_first(self):
        calls = []
        class Pool:
            def submit(self, fn):
                calls.append(("worker", fn()))
                return SimpleNamespace(add_done_callback=lambda cb: None)
        win = SimpleNamespace(_closed=False, _hs_active=True, _hs_concurrent=False, _wifi_workers=Pool())
        with patch.object(hs, "stop", lambda: calls.append(("hotspot stop",))), \
                patch.object(tv.subprocess, "run", return_value=SimpleNamespace(returncode=0)):
            tv.TVWindow._wifi_job(win, ["nmcli", "device", "wifi", "list"], lambda r: None)
        self.assertEqual(calls[0], ("hotspot stop",))
        self.assertFalse(win._hs_active)


if __name__ == "__main__":
    unittest.main()
