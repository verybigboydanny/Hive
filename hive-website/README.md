# Hive website

Static site: HTML, CSS and vanilla JavaScript. No build step.

## Run
Open `index.html` in a browser, or serve the folder:

    npx serve .
    # or
    python3 -m http.server 8000

## Structure
- `index.html`: markup and all pages (hash-routed: #home, #how, #docs, #downloads, #releases, #troubleshooting, #brand)
- `css/styles.css`: design tokens, layout, animations
- `js/main.js`: routing, GSAP animations, hive canvas, scroll story, handoff demo, accent themes
- `assets/brand/`: SVG icon, app icon, monochrome and favicon files

## Notes
- GSAP 3.12.5 and ScrollTrigger load from cdnjs; fonts load from Google Fonts. An internet connection is needed for both.
- Download links, versions, requirements and MCP details are placeholders marked "TBC".
- The hero hive and handoff demo are decorative and do not represent real Hive behaviour.
