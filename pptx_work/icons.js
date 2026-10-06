const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const fa6 = require("react-icons/fa6");

const hex = (c) => (c.startsWith("#") ? c : "#" + c);

// Renders `name` (a react-icons/fa6 export) inset inside a filled circle,
// as a base64 PNG data URI ready for pptxgenjs addImage({data: ...}).
async function iconCircle(name, { size = 256, circleColor, iconColor = "#FFFFFF", iconScale = 0.52 } = {}) {
  const Icon = fa6[name];
  if (!Icon) throw new Error(`Unknown icon ${name}`);
  const markup = ReactDOMServer.renderToStaticMarkup(React.createElement(Icon));
  const inner = markup.replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");
  const iconPx = size * iconScale;
  const offset = (size - iconPx) / 2;
  const svg = `
<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" xmlns="http://www.w3.org/2000/svg">
  <circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}" fill="${hex(circleColor)}"/>
  <g transform="translate(${offset},${offset})" fill="${hex(iconColor)}">
    <svg width="${iconPx}" height="${iconPx}" viewBox="0 0 512 512">${inner}</svg>
  </g>
</svg>`.trim();
  const buf = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + buf.toString("base64");
}

// Plain icon (no circle), transparent background - for small inline icons.
async function iconPlain(name, { size = 256, color = "#FFFFFF" } = {}) {
  const Icon = fa6[name];
  if (!Icon) throw new Error(`Unknown icon ${name}`);
  const markup = ReactDOMServer.renderToStaticMarkup(React.createElement(Icon));
  const inner = markup.replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");
  const svg = `<svg width="${size}" height="${size}" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg" fill="${hex(color)}">${inner}</svg>`;
  const buf = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + buf.toString("base64");
}

module.exports = { iconCircle, iconPlain };
