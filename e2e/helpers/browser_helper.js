const { chromium } = require('../node_modules/playwright-core');
const path = require('path');
const fs = require('fs');

const SCREENSHOTS_DIR = path.join(__dirname, '..', 'screenshots');
if (!fs.existsSync(SCREENSHOTS_DIR)) {
  fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
}

class BrowserHelper {
  constructor(options = {}) {
    this.port = options.port || 8080;
    this.baseUrl = options.baseUrl || `http://127.0.0.1:${this.port}`;
    this.browser = null;
    this.context = null;
    this.page = null;
    this.logs = [];
    this.errors = [];
  }

  async launch(viewport = { width: 1440, height: 900 }, { persistent = true } = {}) {
    if (persistent) {
      const userDataDir = path.join(__dirname, '..', '.chrome_data');
      if (!fs.existsSync(userDataDir)) {
        fs.mkdirSync(userDataDir, { recursive: true });
      }
      this.context = await chromium.launchPersistentContext(userDataDir, {
        executablePath: '/usr/bin/google-chrome',
        headless: true,
        viewport,
        userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
        args: [
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-dev-shm-usage',
          '--disable-gpu',
          '--autoplay-policy=no-user-gesture-required',
        ],
      });
      this.page = this.context.pages()[0] || await this.context.newPage();
    } else {
      this.browser = await chromium.launch({
        executablePath: '/usr/bin/google-chrome',
        args: [
          '--no-sandbox',
          '--disable-setuid-sandbox',
          '--disable-dev-shm-usage',
          '--disable-gpu',
          '--autoplay-policy=no-user-gesture-required',
        ],
      });

      this.context = await this.browser.newContext({
        viewport,
        userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
      });

      this.page = await this.context.newPage();
    }

    this.page.on('console', msg => {
      const entry = `[${msg.type().toUpperCase()}] ${msg.text()}`;
      this.logs.push(entry);
    });

    this.page.on('pageerror', err => {
      this.errors.push(err.message);
    });

    return this.page;
  }

  async navigate(route = '') {
    const targetUrl = route.startsWith('/') ? `${this.baseUrl}/#${route}` : `${this.baseUrl}/#/${route}`;
    await this.page.goto(targetUrl, { waitUntil: 'load', timeout: 30000 });
    
    // Wait for Flutter Web engine & CanvasKit to mount
    await this.waitForFlutterReady();
    await this.enableSemantics();
  }

  async waitForFlutterReady(timeout = 25000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const ready = await this.page.evaluate(() => {
        return !!document.querySelector('flt-glass-pane') || !!document.querySelector('flutter-view');
      });
      if (ready) {
        // Extra settling delay for CanvasKit initial shader compilation
        await this.page.waitForTimeout(3000);
        return true;
      }
      await this.page.waitForTimeout(500);
    }
    return false;
  }

  async enableSemantics(timeout = 15000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const enabled = await this.page.evaluate(() => {
        const placeholder = document.querySelector('flt-semantics-placeholder');
        if (placeholder) {
          placeholder.click();
          return true;
        }
        return false;
      });
      if (enabled) {
        await this.page.waitForTimeout(1500);
        return true;
      }
      await this.page.waitForTimeout(500);
    }
    return false;
  }

  async screenshot(name) {
    const filename = `${name}.png`;
    const filepath = path.join(SCREENSHOTS_DIR, filename);
    await this.page.screenshot({ path: filepath, fullPage: false });
    return filepath;
  }

  async close() {
    if (this.context) {
      await this.context.close();
      this.context = null;
    }
    if (this.browser) {
      await this.browser.close();
      this.browser = null;
    }
  }
}

module.exports = { BrowserHelper, SCREENSHOTS_DIR };
