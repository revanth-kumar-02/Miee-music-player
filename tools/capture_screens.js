const puppeteer = require('/home/rev/.gemini/antigravity-ide/brain/f9ba3e1a-6da9-4afb-a761-ee1846f1bcb0/scratch/puppeteer/node_modules/puppeteer-core');
const fs = require('fs');
const path = require('path');

const ARTIFACT_DIR = '/home/rev/.gemini/antigravity-ide/brain/f9ba3e1a-6da9-4afb-a761-ee1846f1bcb0';

async function capture() {
  const browser = await puppeteer.launch({
    executablePath: '/usr/bin/google-chrome',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-gpu',
      '--enable-unsafe-swiftshader',
      '--disable-dev-shm-usage',
    ],
    defaultViewport: { width: 1536, height: 1024 },
  });

  const page = await browser.newPage();

  page.on('console', msg => {
    console.log(`[BROWSER ${msg.type()}] ${msg.text()}`);
  });

  page.on('pageerror', err => {
    console.error(`[PAGE ERROR]`, err);
  });

  console.log('Navigating to http://localhost:3000/#/home ...');
  await page.goto('http://localhost:3000/#/home', { waitUntil: 'networkidle2', timeout: 30000 });
  
  // Wait 4 seconds for Flutter CanvasKit and fonts to render
  await new Promise(r => setTimeout(r, 4000));

  await page.screenshot({ path: path.join(ARTIFACT_DIR, 'screen_home_desktop.png'), fullPage: false });
  console.log('Saved screen_home_desktop.png');

  // Search screen
  console.log('Navigating to Search ...');
  await page.goto('http://localhost:3000/#/search', { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: path.join(ARTIFACT_DIR, 'screen_search_desktop.png'), fullPage: false });
  console.log('Saved screen_search_desktop.png');

  // Library screen
  console.log('Navigating to Library ...');
  await page.goto('http://localhost:3000/#/playlists', { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: path.join(ARTIFACT_DIR, 'screen_library_desktop.png'), fullPage: false });
  console.log('Saved screen_library_desktop.png');

  // Login screen
  console.log('Navigating to Login ...');
  await page.goto('http://localhost:3000/#/login', { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: path.join(ARTIFACT_DIR, 'screen_login_desktop.png'), fullPage: false });
  console.log('Saved screen_login_desktop.png');

  // Player screen
  console.log('Navigating to Player ...');
  await page.goto('http://localhost:3000/#/player', { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: path.join(ARTIFACT_DIR, 'screen_player_desktop.png'), fullPage: false });
  console.log('Saved screen_player_desktop.png');

  // Tablet viewport (768 x 1024)
  console.log('Capturing Tablet viewport (768x1024) ...');
  await page.setViewport({ width: 768, height: 1024 });
  await page.goto('http://localhost:3000/#/home', { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: path.join(ARTIFACT_DIR, 'screen_home_tablet.png'), fullPage: false });
  console.log('Saved screen_home_tablet.png');

  // Mobile viewport (390 x 844)
  console.log('Capturing Mobile viewport (390x844) ...');
  await page.setViewport({ width: 390, height: 844 });
  await page.goto('http://localhost:3000/#/home', { waitUntil: 'networkidle2', timeout: 30000 });
  await new Promise(r => setTimeout(r, 3000));
  await page.screenshot({ path: path.join(ARTIFACT_DIR, 'screen_home_mobile.png'), fullPage: false });
  console.log('Saved screen_home_mobile.png');

  await browser.close();
  console.log('All screenshots captured successfully!');
}

capture().catch(err => {
  console.error('Fatal error during capture:', err);
  process.exit(1);
});
