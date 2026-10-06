const fs = require("fs");
const pptxgen = require("pptxgenjs");
const { iconCircle } = require("./icons.js");

const BRACK_LOGO = "image/png;base64," + fs.readFileSync(__dirname + "/brack_logo.png").toString("base64");

// ---------------------------------------------------------------- palette
const BG = "14141C";
const CARD = "1E1E2E";
const PINK = "FF2E92";
const LIME = "E8FF3D";
const PURPLE = "5B4B9E";
const TEXT = "F5F5F7";
const MUTED = "A8A8BC";

const FONT_HEAD = "Arial";
const FONT_BODY = "Calibri";

const W = 13.333, H = 7.5;
const MARGIN = 0.6;

async function main() {
  const pptx = new pptxgen();
  pptx.defineLayout({ name: "WIDE", width: W, height: H });
  pptx.layout = "WIDE";

  // ------------------------------------------------------------ icon cache
  const I = {};
  const need = [
    ["Tv", "FaTv"], ["Microchip", "FaMicrochip"], ["Sliders", "FaSliders"],
    ["Power", "FaPowerOff"], ["Gamepad", "FaGamepad"], ["Plug", "FaPlug"],
    ["Lightbulb", "FaLightbulb"], ["Recycle", "FaRecycle"],
    ["Triangle", "FaTriangleExclamation"], ["Wrench", "FaWrench"],
    ["Sitemap", "FaSitemap"], ["Bullseye", "FaBullseye"],
    ["VolumeHigh", "FaVolumeHigh"], ["VolumeX", "FaVolumeXmark"],
    ["LinkSlash", "FaLinkSlash"], ["Keyboard", "FaKeyboard"],
    ["Terminal", "FaTerminal"], ["Bolt", "FaBolt"], ["Database", "FaDatabase"],
    ["Rotate", "FaArrowsRotate"], ["Usb", "FaUsb"], ["Ethernet", "FaEthernet"],
    ["CheckCircle", "FaCircleCheck"], ["ScrewdriverWrench", "FaScrewdriverWrench"],
    ["Satellite", "FaSatelliteDish"], ["Display", "FaDisplay"], ["ListOl", "FaListOl"],
    ["Trophy", "FaTrophy"], ["Earth", "FaEarthAmericas"], ["CircleQuestion", "FaCircleQuestion"],
  ];
  for (const [key, name] of need) {
    I[key + "_pink"] = await iconCircle(name, { circleColor: PINK });
    I[key + "_lime"] = await iconCircle(name, { circleColor: LIME, iconColor: "1A1A22" });
    I[key + "_purple"] = await iconCircle(name, { circleColor: PURPLE });
  }

  // ------------------------------------------------------------ helpers
  const LOGO_RATIO = 639 / 1285;
  const LOGO_H = 0.42;
  const LOGO_W = LOGO_H * LOGO_RATIO;

  function newSlide() {
    const s = pptx.addSlide();
    s.background = { color: BG };
    s.addImage({
      data: BRACK_LOGO,
      x: W - LOGO_W - 0.35, y: H - LOGO_H - 0.3, w: LOGO_W, h: LOGO_H,
    });
    return s;
  }

  function title(s, text, opts = {}) {
    s.addText(text, {
      x: MARGIN, y: 0.8, w: W - MARGIN * 2, h: 0.7,
      fontFace: FONT_HEAD, fontSize: opts.size || 30, bold: true,
      color: PINK, align: opts.align || "left", isTextBox: true, margin: 0,
    });
  }

  function kicker(s, text) {
    s.addText(text.toUpperCase(), {
      x: MARGIN, y: 0.42, w: W - MARGIN * 2, h: 0.32,
      fontFace: FONT_BODY, fontSize: 12, bold: true, color: MUTED,
      charSpacing: 2, isTextBox: true, margin: 0,
    });
  }

  // icon-circle card: icon on top, header, short description
  function iconCard(s, { x, y, w, icon, header, desc, headerColor = TEXT }) {
    const iconSize = 0.62;
    s.addImage({ data: icon, x: x + w / 2 - iconSize / 2, y, w: iconSize, h: iconSize });
    s.addText(header, {
      x, y: y + iconSize + 0.12, w, h: 0.55,
      fontFace: FONT_HEAD, fontSize: 14.5, bold: true, color: headerColor,
      align: "center", isTextBox: true, margin: 0, valign: "top",
    });
    if (desc) {
      s.addText(desc, {
        x, y: y + iconSize + 0.64, w, h: 1.15,
        fontFace: FONT_BODY, fontSize: 11.5, color: MUTED,
        align: "center", isTextBox: true, margin: 0, valign: "top",
      });
    }
  }

  // left-aligned icon row: icon left, header+desc stacked right
  function iconRow(s, { x, y, w, icon, header, desc, headerSize = 14 }) {
    const iconSize = 0.55;
    s.addImage({ data: icon, x, y, w: iconSize, h: iconSize });
    s.addText(header, {
      x: x + iconSize + 0.22, y: y - 0.05, w: w - iconSize - 0.22, h: 0.35,
      fontFace: FONT_HEAD, fontSize: headerSize, bold: true, color: TEXT,
      isTextBox: true, margin: 0,
    });
    if (desc) {
      s.addText(desc, {
        x: x + iconSize + 0.22, y: y + 0.3, w: w - iconSize - 0.22, h: 0.6,
        fontFace: FONT_BODY, fontSize: 11, color: MUTED,
        isTextBox: true, margin: 0,
      });
    }
  }

  function pageNum(s, n) {
    s.addText(String(n).padStart(2, "0"), {
      x: MARGIN, y: H - 0.55, w: 0.6, h: 0.35,
      fontFace: FONT_BODY, fontSize: 10, color: MUTED, align: "left",
      isTextBox: true, margin: 0,
    });
  }

  function sectionDivider(n, num, name, iconKey, subtitle) {
    const s = newSlide();
    s.addImage({ data: I[iconKey + "_pink"], x: W / 2 - 0.9, y: 1.5, w: 1.8, h: 1.8 });
    s.addText(num, {
      x: 0, y: 3.35, w: W, h: 0.5, align: "center",
      fontFace: FONT_HEAD, fontSize: 16, bold: true, color: LIME,
      charSpacing: 4, isTextBox: true, margin: 0,
    });
    s.addText(name.toUpperCase(), {
      x: 0, y: 3.85, w: W, h: 0.9, align: "center",
      fontFace: FONT_HEAD, fontSize: 40, bold: true, color: TEXT,
      isTextBox: true, margin: 0,
    });
    s.addText(subtitle, {
      x: W / 2 - 3.5, y: 4.75, w: 7, h: 0.5, align: "center",
      fontFace: FONT_BODY, fontSize: 14, color: MUTED,
      isTextBox: true, margin: 0,
    });
    pageNum(s, n);
    return s;
  }

  // ============================================================
  // SLIDE 1 - Title
  // ============================================================
  {
    const s = newSlide();
    s.addImage({ data: I.Tv_pink, x: W - 4.6, y: H / 2 - 1.5, w: 3, h: 3 });
    s.addText("RETRO TV", {
      x: MARGIN, y: 2.5, w: 7.5, h: 1.0,
      fontFace: FONT_HEAD, fontSize: 52, bold: true, color: TEXT,
      isTextBox: true, margin: 0,
    });
    s.addText("PROJECT", {
      x: MARGIN, y: 3.35, w: 7.5, h: 1.0,
      fontFace: FONT_HEAD, fontSize: 52, bold: true, color: PINK,
      isTextBox: true, margin: 0,
    });
    s.addText("By Haidar Ali Alshowaikh   |   Class 8E", {
      x: MARGIN, y: 4.45, w: 7.5, h: 0.5,
      fontFace: FONT_BODY, fontSize: 16, color: MUTED,
      isTextBox: true, margin: 0,
    });
  }

  // ============================================================
  // SLIDE 2 - Materials (icon grid)
  // ============================================================
  {
    const s = newSlide();
    kicker(s, "What it's built from");
    title(s, "Materials Used");
    const items = [
      ["Microchip_lime", "Raspberry Pi"], ["Microchip_pink", "Arduino Uno"],
      ["Sliders_lime", "Potentiometer 10K"], ["Ethernet_pink", "Jumper Wires"],
      ["Power_lime", "Button"], ["Gamepad_pink", "Joystick Module"],
      ["Display_lime", "Old Laptop Screen"], ["Plug_pink", "HDMI Module"],
    ];
    const cols = 4, rows = 2, cw = (W - MARGIN * 2) / cols, ch = 2.15;
    items.forEach(([icon, label], idx) => {
      const c = idx % cols, r = Math.floor(idx / cols);
      iconCard(s, {
        x: MARGIN + c * cw, y: 1.7 + r * ch, w: cw,
        icon: I[icon], header: label,
      });
    });
    pageNum(s, 2);
  }

  // ============================================================
  // SLIDE 3 - Agenda
  // ============================================================
  {
    const s = newSlide();
    kicker(s, "Roadmap");
    title(s, "What's Ahead");
    const items = [
      ["Lightbulb_pink", "01", "The Idea", "How I got the idea"],
      ["Triangle_lime", "02", "The Problems", "What went wrong along the way"],
      ["Wrench_pink", "03", "Solutions", "How each problem got fixed"],
      ["Sitemap_lime", "04", "The Wiring", "How every part connects"],
      ["Bullseye_pink", "05", "Goals", "What the project set out to do"],
    ];
    const cw = (W - MARGIN * 2) / items.length;
    items.forEach(([icon, num, header, desc], idx) => {
      const x = MARGIN + idx * cw;
      s.addImage({ data: I[icon], x: x + cw / 2 - 0.35, y: 1.75, w: 0.7, h: 0.7 });
      s.addText(num, {
        x, y: 2.55, w: cw, h: 0.4, align: "center",
        fontFace: FONT_HEAD, fontSize: 13, bold: true, color: MUTED,
        isTextBox: true, margin: 0,
      });
      s.addText(header, {
        x, y: 2.95, w: cw, h: 0.4, align: "center",
        fontFace: FONT_HEAD, fontSize: 15, bold: true, color: TEXT,
        isTextBox: true, margin: 0,
      });
      s.addText(desc, {
        x: x + 0.15, y: 3.4, w: cw - 0.3, h: 1.3, align: "center",
        fontFace: FONT_BODY, fontSize: 10.5, color: MUTED,
        isTextBox: true, margin: 0,
      });
    });
    pageNum(s, 3);
  }

  // ============================================================ Section 1
  sectionDivider(4, "SECTION 01", "The Idea", "Lightbulb", "How I got the idea");

  // SLIDE 5
  {
    const s = newSlide();
    kicker(s, "Section 01 · The Idea");
    title(s, "The Laptop...");
    s.addImage({ data: I.Recycle_pink, x: W - 3.6, y: 2.3, w: 2.2, h: 2.2 });
    s.addText(
      "I found a laptop that we don't use any more, so I thought of recycling it and giving it a new purpose.",
      {
        x: MARGIN, y: 2.4, w: 7.2, h: 2.0,
        fontFace: FONT_BODY, fontSize: 20, color: TEXT,
        isTextBox: true, margin: 0, valign: "top",
      }
    );
    pageNum(s, 5);
  }

  // ============================================================ Section 2
  sectionDivider(6, "SECTION 02", "The Problems", "Triangle", "What went wrong along the way");

  // SLIDE 7 - native chart
  {
    const s = newSlide();
    kicker(s, "Section 02 · The Problems");
    title(s, "Problems By Type");
    s.addChart(pptx.ChartType.bar, [
      {
        name: "Share of problems",
        labels: ["Software", "Hardware"],
        values: [60, 40],
      },
    ], {
      x: MARGIN, y: 1.75, w: 5.7, h: 3.2,
      barDir: "bar",
      chartColors: [LIME],
      showTitle: true, title: "Software vs Hardware", titleColor: TEXT, titleFontSize: 13,
      showValue: true, dataLabelColor: TEXT, dataLabelFontSize: 12, dataLabelPosition: "outEnd",
      catAxisLabelColor: MUTED, valAxisHidden: true,
      catAxisLineShow: false, valAxisLineShow: false,
      showLegend: false,
      plotArea: { fill: { color: BG } }, chartArea: { fill: { color: BG } },
      valGridLine: { style: "none" }, catGridLine: { style: "none" },
    });
    s.addText("TIME TO FIX", {
      x: 6.9, y: 1.85, w: 5.8, h: 0.4,
      fontFace: FONT_HEAD, fontSize: 14, bold: true, color: TEXT,
      isTextBox: true, margin: 0,
    });
    const bars = [["Under a day", 35], ["Multiple days", 75]];
    bars.forEach(([label, pct], i) => {
      const y = 2.5 + i * 0.85;
      s.addText(label, {
        x: 6.9, y, w: 5.8, h: 0.3,
        fontFace: FONT_BODY, fontSize: 12, color: MUTED, isTextBox: true, margin: 0,
      });
      s.addShape(pptx.ShapeType.roundRect, {
        x: 6.9, y: y + 0.32, w: 5.8, h: 0.16, fill: { color: CARD }, line: { type: "none" },
        rectRadius: 0.08,
      });
      s.addShape(pptx.ShapeType.roundRect, {
        x: 6.9, y: y + 0.32, w: 5.8 * (pct / 100), h: 0.16, fill: { color: PINK }, line: { type: "none" },
        rectRadius: 0.08,
      });
    });
    pageNum(s, 7);
  }

  // SLIDE 8
  {
    const s = newSlide();
    kicker(s, "Section 02 · The Problems");
    title(s, "Biggest Time Sinks");
    const items = [
      ["VolumeHigh_pink", "35%", "Tracking down the PipeWire bug that sent audio out the wrong HDMI port"],
      ["Gamepad_lime", "40%", "Getting the joystick reliably read as arrow keys under the Wayland compositor"],
      ["LinkSlash_pink", "25%", "Repairing the LCD panel after its LVDS connector latch broke"],
    ];
    const cw = (W - MARGIN * 2 - 0.6) / 3;
    items.forEach(([icon, pct, desc], i) => {
      const x = MARGIN + i * (cw + 0.3);
      s.addImage({ data: I[icon], x: x + cw / 2 - 0.4, y: 1.75, w: 0.8, h: 0.8 });
      s.addText(pct, {
        x, y: 2.7, w: cw, h: 0.6, align: "center",
        fontFace: FONT_HEAD, fontSize: 30, bold: true, color: TEXT,
        isTextBox: true, margin: 0,
      });
      s.addText(desc, {
        x, y: 3.35, w: cw, h: 1.6, align: "center",
        fontFace: FONT_BODY, fontSize: 12, color: MUTED,
        isTextBox: true, margin: 0, valign: "top",
      });
    });
    pageNum(s, 8);
  }

  // SLIDE 9 - single clean table
  {
    const s = newSlide();
    kicker(s, "Section 02 · The Problems");
    title(s, "Component Issues");
    const rows = [
      [{ text: "COMPONENT", options: { bold: true, color: LIME } }, { text: "ISSUE", options: { bold: true, color: LIME } }],
      ["Audio output", "Routed to the wrong HDMI port"],
      ["Volume knob", "Changed app AND system volume at once"],
      ["LCD panel", "Connector latch broke during repair"],
      ["Joystick hole", "Wider than the module's own screws"],
      ["Speaker grille", "Size was an unconfirmed placeholder"],
      ["Volume keys", "Real multimedia keys grabbed by the desktop"],
    ].map(row => Array.isArray(row) ? row.map(c => typeof c === "string" ? { text: c, options: { color: TEXT } } : c) : row);
    s.addTable(rows, {
      x: MARGIN, y: 1.8, w: W - MARGIN * 2, h: 4.6,
      fontFace: FONT_BODY, fontSize: 13,
      border: { type: "solid", color: CARD, pt: 1 },
      fill: { color: CARD },
      autoPage: false,
      valign: "middle",
      colW: [(W - MARGIN * 2) * 0.32, (W - MARGIN * 2) * 0.68],
      rowH: 0.6,
    });
    pageNum(s, 9);
  }

  // SLIDE 10
  {
    const s = newSlide();
    kicker(s, "Section 02 · The Problems");
    title(s, "Four Main Problems");
    const items = [
      ["VolumeHigh_pink", "Audio Routing", "mpv sent sound out the wrong HDMI port"],
      ["VolumeX_lime", "Volume Control", "The knob changed app and system volume together"],
      ["LinkSlash_pink", "Screen Connector", "The connector latch snapped during repair"],
      ["Gamepad_lime", "Hole vs Screws", "Joystick hole ended up wider than its screws"],
    ];
    const cols = 2, cw = (W - MARGIN * 2 - 0.4) / 2, ch = 2.3;
    items.forEach(([icon, header, desc], idx) => {
      const c = idx % cols, r = Math.floor(idx / cols);
      const x = MARGIN + c * (cw + 0.4), y = 1.75 + r * ch;
      iconRow(s, { x, y: y + 0.1, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 10);
  }

  // ============================================================ Section 3
  sectionDivider(11, "SECTION 03", "Solutions", "Wrench", "How each problem got fixed");

  // SLIDE 12
  {
    const s = newSlide();
    kicker(s, "Section 03 · Solutions");
    title(s, "How I Fixed Them");
    const items = [
      ["VolumeHigh_pink", "System Volume", "Volume knob now calls wpctl to change the real speaker"],
      ["Ethernet_lime", "Audio Device", "mpv points straight at the correct ALSA HDMI device"],
      ["Keyboard_pink", "Key Detection", "Checks both the keysym and the raw hardware keycode"],
    ];
    const cw = (W - MARGIN * 2 - 0.6) / 3;
    items.forEach(([icon, header, desc], i) => {
      const x = MARGIN + i * (cw + 0.3);
      iconCard(s, { x, y: 1.85, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 12);
  }

  // SLIDE 13
  {
    const s = newSlide();
    kicker(s, "Section 03 · Solutions");
    title(s, "Debugging Toolbox");
    const items = [
      ["Terminal_pink", "wpctl status", "Check where audio was actually routing"],
      ["Keyboard_lime", "key_debug.py", "Print the real keycode for any key"],
      ["Bolt_pink", "Flashlight test", "Tell a dead backlight from dead video"],
      ["Database_lime", "iptv-org", "Verify channels before adding them"],
      ["Sitemap_pink", "BFS check", "Prove the keyboard is joystick-reachable"],
      ["Rotate_lime", "Round-trip test", "Verify the installer before sending it"],
    ];
    const cols = 3, cw = (W - MARGIN * 2 - 0.6) / cols, ch = 2.5;
    items.forEach(([icon, header, desc], idx) => {
      const c = idx % cols, r = Math.floor(idx / cols);
      const x = MARGIN + c * (cw + 0.3), y = 1.8 + r * ch;
      iconCard(s, { x, y, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 13);
  }

  // SLIDE 14
  {
    const s = newSlide();
    kicker(s, "Section 03 · Solutions");
    title(s, "Where This Stands Now");
    s.addImage({ data: I.CheckCircle_lime, x: W - 3.6, y: 2.4, w: 2.0, h: 2.0 });
    s.addText(
      "Every major software problem has a working fix - audio, volume control, and key detection are all solid.",
      { x: MARGIN, y: 2.5, w: 7.0, h: 1.0, fontFace: FONT_BODY, fontSize: 17, color: TEXT, isTextBox: true, margin: 0 }
    );
    s.addText(
      "The screen connector repair is still in progress.",
      { x: MARGIN, y: 3.5, w: 7.0, h: 0.6, fontFace: FONT_BODY, fontSize: 17, color: MUTED, isTextBox: true, margin: 0 }
    );
    pageNum(s, 14);
  }

  // ============================================================ Section 4
  sectionDivider(15, "SECTION 04", "The Wiring", "Sitemap", "How every part connects");

  // SLIDE 16
  {
    const s = newSlide();
    kicker(s, "Section 04 · The Wiring");
    title(s, "Wiring Overview");
    const items = [
      ["Gamepad_pink", "Joystick", "Arduino digital pins, plus one for the click button"],
      ["Sliders_lime", "Volume Knob", "A 10K potentiometer on an Arduino analog input"],
      ["Power_pink", "Power Button", "Its own pin, held 2 seconds to shut down"],
      ["Microchip_lime", "Arduino -> Pi", "USB, sending plain text commands over serial"],
      ["Ethernet_pink", "Pi -> Driver Board", "HDMI into the universal LCD controller board"],
      ["Tv_lime", "Board -> Screen", "LVDS ribbon plus a separate backlight connector"],
    ];
    const cols = 3, cw = (W - MARGIN * 2 - 0.6) / cols, ch = 2.5;
    items.forEach(([icon, header, desc], idx) => {
      const c = idx % cols, r = Math.floor(idx / cols);
      const x = MARGIN + c * (cw + 0.3), y = 1.8 + r * ch;
      iconCard(s, { x, y, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 16);
  }

  // SLIDE 17
  {
    const s = newSlide();
    kicker(s, "Section 04 · The Wiring");
    title(s, "How A Button Press Travels");
    const items = [
      ["Microchip_pink", "1. ARDUINO", "Reads the joystick, knob, and button; sends a command over serial"],
      ["Rotate_lime", "2. THE BRIDGE", "rpi_bridge.py turns that command into a real key or mouse event"],
      ["Tv_pink", "3. THE APP", "tv.py receives it like normal keyboard input and reacts on screen"],
    ];
    const cw = (W - MARGIN * 2 - 0.6) / 3;
    items.forEach(([icon, header, desc], i) => {
      const x = MARGIN + i * (cw + 0.3);
      iconCard(s, { x, y: 2.0, w: cw, icon: I[icon], header, desc });
      if (i < 2) {
        s.addText("→", {
          x: x + cw + 0.02, y: 2.15, w: 0.26, h: 0.6, align: "center",
          fontFace: FONT_HEAD, fontSize: 26, bold: true, color: MUTED,
          isTextBox: true, margin: 0,
        });
      }
    });
    pageNum(s, 17);
  }

  // SLIDE 18
  {
    const s = newSlide();
    kicker(s, "Section 04 · The Wiring");
    title(s, "Wiring In Progress");
    s.addImage({ data: I.Sitemap_pink, x: W - 3.6, y: 2.3, w: 2.2, h: 2.2 });
    s.addText(
      "Every input component runs back to the Arduino on its own pin, and the Arduino talks to the Pi over a single USB serial cable.",
      { x: MARGIN, y: 2.4, w: 7.2, h: 1.8, fontFace: FONT_BODY, fontSize: 18, color: TEXT, isTextBox: true, margin: 0, valign: "top" }
    );
    pageNum(s, 18);
  }

  // SLIDE 19
  {
    const s = newSlide();
    kicker(s, "Section 04 · The Wiring");
    title(s, "The Finished Build");
    s.addImage({ data: I.Gamepad_lime, x: W / 2 - 1.1, y: 2.3, w: 2.2, h: 2.2 });
    pageNum(s, 19);
  }

  // SLIDE 20
  {
    const s = newSlide();
    kicker(s, "Section 04 · The Wiring");
    title(s, "Three Main Connections");
    const items = [
      ["Usb_pink", "USB Serial", "Arduino to Pi, carrying every joystick, knob, and button command"],
      ["Microchip_lime", "GPIO", "The power button wired straight to the Pi for a direct shutdown"],
      ["Plug_pink", "HDMI", "Pi to the driver board, carrying video to the recycled screen"],
    ];
    const cw = (W - MARGIN * 2 - 0.6) / 3;
    items.forEach(([icon, header, desc], i) => {
      const x = MARGIN + i * (cw + 0.3);
      iconCard(s, { x, y: 1.85, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 20);
  }

  // SLIDE 21
  {
    const s = newSlide();
    kicker(s, "Section 04 · The Wiring");
    title(s, "Wiring Reference Table");
    const head = ["", "PORT A", "PORT B", "PORT C"].map(t => ({ text: t, options: { bold: true, color: LIME } }));
    const data = [
      ["ARDUINO", "Joystick X/Y/click", "Knob wiper", "Button pin"],
      ["PI", "USB from Arduino", "HDMI to driver board", "GPIO to power button"],
      ["DRIVER BOARD", "HDMI in", "LVDS out to panel", "Backlight power out"],
      ["SCREEN", "LVDS in", "Backlight in", "-"],
      ["POWER", "5V to Pi", "12V to driver board", "Shared ground"],
    ].map(row => row.map((c, i) => ({ text: c, options: { color: i === 0 ? TEXT : MUTED, bold: i === 0 } } )));
    s.addTable([head, ...data], {
      x: MARGIN, y: 1.8, w: W - MARGIN * 2, h: 4.6,
      fontFace: FONT_BODY, fontSize: 12.5,
      border: { type: "solid", color: CARD, pt: 1 },
      fill: { color: CARD },
      autoPage: false, valign: "middle",
      rowH: 0.7,
    });
    pageNum(s, 21);
  }

  // SLIDE 22
  {
    const s = newSlide();
    kicker(s, "Section 04 · The Wiring");
    title(s, "Build Milestones");
    const items = [
      ["Microchip_pink", "STEP 1", "Wire joystick, knob, and button to the Arduino"],
      ["Terminal_lime", "STEP 2", "Flash the Arduino sketch, test raw serial output"],
      ["Rotate_pink", "STEP 3", "Get rpi_bridge.py turning serial into key events"],
      ["Sitemap_lime", "STEP 4", "Wire the driver board, screen, and power button"],
    ];
    const cw = (W - MARGIN * 2 - 0.9) / 4;
    items.forEach(([icon, header, desc], i) => {
      const x = MARGIN + i * (cw + 0.3);
      iconCard(s, { x, y: 1.9, w: cw, icon: I[icon], header, desc });
      if (i < 3) {
        s.addText("→", {
          x: x + cw + 0.02, y: 2.05, w: 0.26, h: 0.6, align: "center",
          fontFace: FONT_HEAD, fontSize: 20, bold: true, color: MUTED,
          isTextBox: true, margin: 0,
        });
      }
    });
    pageNum(s, 22);
  }

  // ============================================================ Section 5
  sectionDivider(23, "SECTION 05", "Goals", "Bullseye", "What the project set out to do");

  // SLIDE 24
  {
    const s = newSlide();
    kicker(s, "Section 05 · Goals");
    title(s, "Goals");
    const items = [
      ["Tv_pink", "GOAL 1", "Build a fully working retro TV, controllable end-to-end with just the joystick"],
      ["ScrewdriverWrench_lime", "GOAL 2", "Fit everything into a custom laser-cut enclosure sized for the recycled screen"],
    ];
    const cw = (W - MARGIN * 2 - 0.6) / 2;
    items.forEach(([icon, header, desc], i) => {
      const x = MARGIN + i * (cw + 0.6);
      iconCard(s, { x, y: 2.0, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 24);
  }

  // SLIDE 25 - big number
  {
    const s = newSlide();
    s.addShape(pptx.ShapeType.roundRect, {
      x: W / 2 - 3.6, y: 1.1, w: 7.2, h: 5.0, fill: { color: CARD }, line: { type: "none" }, rectRadius: 0.15,
    });
    s.addImage({ data: I.Satellite_lime, x: W / 2 - 0.55, y: 1.55, w: 1.1, h: 1.1 });
    s.addText("264", {
      x: 0, y: 2.8, w: W, h: 1.3, align: "center",
      fontFace: FONT_HEAD, fontSize: 76, bold: true, color: PINK,
      isTextBox: true, margin: 0,
    });
    s.addText("Channels curated for the custom IPTV channel list, each checked twice before being added", {
      x: W / 2 - 3.0, y: 4.35, w: 6.0, h: 1.1, align: "center",
      fontFace: FONT_BODY, fontSize: 15, color: MUTED,
      isTextBox: true, margin: 0,
    });
    pageNum(s, 25);
  }

  // ============================================================ Section 6
  sectionDivider(26, "SECTION 06", "Project Fair", "Trophy", "How this project fits what judges look for");

  // SLIDE 27
  {
    const s = newSlide();
    kicker(s, "Section 06 · Project Fair");
    title(s, "Why This Fits The Fair");
    const items = [
      ["CircleQuestion_pink", "Real Problem Solved", "Built a working alternative instead of buying a new TV"],
      ["Sitemap_lime", "Engineering Process", "Idea, problems, solutions, wiring, and testing - all documented"],
      ["Recycle_pink", "Sustainability", "Gave a retired laptop screen a second life instead of e-waste"],
      ["Lightbulb_lime", "Original Build", "Custom Arduino + Pi software, not an off-the-shelf kit"],
    ];
    const cols = 2, cw = (W - MARGIN * 2 - 0.4) / 2, ch = 2.3;
    items.forEach(([icon, header, desc], idx) => {
      const c = idx % cols, r = Math.floor(idx / cols);
      const x = MARGIN + c * (cw + 0.4), y = 1.75 + r * ch;
      iconRow(s, { x, y: y + 0.1, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 27);
  }

  // SLIDE 28
  {
    const s = newSlide();
    kicker(s, "Section 06 · Project Fair");
    title(s, "Real-World Impact");
    const items = [
      ["Earth_lime", "Less E-Waste", "One fewer laptop thrown out - the screen and body both got reused"],
      ["ScrewdriverWrench_pink", "Skills, Not Just Parts", "Wiring, embedded software, and enclosure design in one build"],
      ["Trophy_lime", "Built To Show", "Everything here actually works, live, not just on paper"],
    ];
    const cw = (W - MARGIN * 2 - 0.6) / 3;
    items.forEach(([icon, header, desc], i) => {
      const x = MARGIN + i * (cw + 0.3);
      iconCard(s, { x, y: 1.85, w: cw, icon: I[icon], header, desc });
    });
    pageNum(s, 28);
  }

  // SLIDE 29 - closing
  {
    const s = newSlide();
    s.addImage({ data: I.Tv_pink, x: W / 2 - 0.9, y: 1.15, w: 1.8, h: 1.8 });
    s.addText("THANKS!", {
      x: 0, y: 3.15, w: W, h: 1.0, align: "center",
      fontFace: FONT_HEAD, fontSize: 44, bold: true, color: TEXT,
      isTextBox: true, margin: 0,
    });
    s.addText("Haidar Ali Alshowaikh  |  Class 8E", {
      x: 0, y: 4.15, w: W, h: 0.5, align: "center",
      fontFace: FONT_BODY, fontSize: 16, color: MUTED,
      isTextBox: true, margin: 0,
    });
    const socials = [
      ["YouTube", "@brackstudy"],
      ["YouTube", "@brackstudy_arabic"],
      ["Instagram", "@brackstudy"],
      ["Instagram", "@brackstudy_arabic"],
    ];
    const cols = 2, gap = 0.3, cardW = 2.9, cardH = 0.55;
    const gridW = cardW * cols + gap;
    const gx = W / 2 - gridW / 2;
    const gy = 5.05;
    socials.forEach(([platform, handle], idx) => {
      const c = idx % cols, r = Math.floor(idx / cols);
      const x = gx + c * (cardW + gap), y = gy + r * (cardH + 0.15);
      s.addText([
        { text: platform + "  ", options: { color: LIME, bold: true } },
        { text: handle, options: { color: TEXT } },
      ], {
        x, y, w: cardW, h: cardH, align: "center", valign: "middle",
        fontFace: FONT_BODY, fontSize: 13, isTextBox: true, margin: 0,
      });
    });
  }

  const OUT = __dirname + "\\deck_redesigned.pptx";
  await pptx.writeFile({ fileName: OUT });
  console.log("Saved", OUT);
}

main().catch(e => { console.error(e); process.exit(1); });
