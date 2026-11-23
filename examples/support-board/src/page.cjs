function renderPage() {
    return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Support desk</title><style>:root { color-scheme: light; font: 16px/1.5 system-ui,sans-serif; color: #17332c; background: #f0f4ed; }
* { box-sizing: border-box; }
body { margin: 0; }
main { max-width: 48rem; margin: 8vh auto; padding: 2rem; }
header { border-bottom: 1px solid #a8b9ac; padding-bottom: 1rem; font-weight: 650; }
h1 { margin: 2rem 0 .5rem; font-size: clamp(2.2rem,6vw,3.8rem); line-height: 1.05; }
p { color: #375348; }
dl { display: flex; flex-wrap: wrap; gap: 1rem; margin: 2rem 0; }
dl div { flex: 1 1 10rem; background: #fff; padding: 1.3rem; border: 1px solid #b9c9bd; border-top: 4px solid #257052; }
dt { font-weight: 650; }
dd { margin: .2rem 0 0; font-size: 3.5rem; line-height: 1.2; font-variant-numeric: tabular-nums; }</style></head>
<body><main><header>Support desk</header><h1>Team queue</h1><p>The local service is ready.</p></main></body></html>`;
}

module.exports = { renderPage };
