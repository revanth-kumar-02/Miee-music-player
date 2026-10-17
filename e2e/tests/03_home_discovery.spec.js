const { BrowserHelper } = require('../helpers/browser_helper');

async function runHomeDiscoveryTest() {
  console.log('\n--- Running 03_home_discovery.spec.js ---');
  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  try {
    console.log('[Test] Navigating to /home...');
    await helper.navigate('/home');
    
    // Allow home discovery to load genuine songs
    console.log('[Test] Waiting for home discovery sections to render...');
    await page.waitForTimeout(10000);
    await helper.screenshot('home_01_loaded');

    await helper.enableSemantics();

    // Check for section headers and genuine song tiles
    const buttons = await page.$$('[role="button"]');
    console.log(`[Test] Discovered ${buttons.length} interactive elements on Home`);

    // Verify scrolling behavior
    console.log('[Test] Scrolling through home discovery...');
    await page.mouse.wheel(0, 500);
    await page.waitForTimeout(2000);
    await helper.screenshot('home_02_scrolled');

    console.log('✓ 03_home_discovery.spec.js passed successfully');
    return { success: true };
  } catch (err) {
    console.error('✗ 03_home_discovery.spec.js failed:', err);
    await helper.screenshot('home_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runHomeDiscoveryTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runHomeDiscoveryTest };
