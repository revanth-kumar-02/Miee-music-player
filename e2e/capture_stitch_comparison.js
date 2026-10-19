const { chromium } = require('./node_modules/playwright-core');
const path = require('path');
const fs = require('fs');

const ARTIFACT_DIR = '/home/rev/.gemini/antigravity-ide/brain/ba6495dd-7d53-422d-b548-ea73b99b5b5b';
const SCREENSHOTS_DIR = path.join(__dirname, 'screenshots');

async function capture() {
  const browser = await chromium.launch({
    executablePath: '/usr/bin/google-chrome',
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
    ],
  });

  const targets = [
    { name: 'login_mobile', url: 'http://127.0.0.1:8080/#/login', width: 390, height: 844 },
    { name: 'login_desktop', url: 'http://127.0.0.1:8080/#/login', width: 1280, height: 800 },
    { name: 'register_mobile', url: 'http://127.0.0.1:8080/#/register', width: 390, height: 844 },
    { name: 'register_desktop', url: 'http://127.0.0.1:8080/#/register', width: 1280, height: 800 },
    { name: 'onboarding_mobile', url: 'http://127.0.0.1:8080/#/onboarding', width: 390, height: 844 },
    { name: 'onboarding_desktop', url: 'http://127.0.0.1:8080/#/onboarding', width: 1280, height: 800 },
  ];

  for (const target of targets) {
    console.log(`Capturing ${target.name} (${target.width}x${target.height}) at ${target.url}...`);
    const context = await browser.newContext({
      viewport: { width: target.width, height: target.height },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();

    try {
      await page.goto(target.url, { waitUntil: 'networkidle', timeout: 30000 });
      // Flutter canvas rendering wait
      await page.waitForTimeout(4000);

      const shotPath = path.join(SCREENSHOTS_DIR, `${target.name}.png`);
      const artifactPath = path.join(ARTIFACT_DIR, `${target.name}.png`);
      await page.screenshot({ path: shotPath });
      fs.copyFileSync(shotPath, artifactPath);
      console.log(`Saved screenshot to ${shotPath} and ${artifactPath}`);
    } catch (err) {
      console.error(`Error capturing ${target.name}:`, err.message);
    } finally {
      await context.close();
    }
  }

  await browser.close();
  console.log('Capture finished!');
}

capture().catch(err => {
  console.error('Fatal error during capture:', err);
  process.exit(1);
});
