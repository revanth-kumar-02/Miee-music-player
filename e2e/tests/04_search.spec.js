const { BrowserHelper } = require('../helpers/browser_helper');

async function runSearchTest() {
  console.log('\n--- Running 04_search.spec.js ---');
  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  try {
    console.log('[Test] Navigating to /search...');
    await helper.navigate('/search');
    await page.waitForTimeout(3000);
    await helper.screenshot('search_01_empty');

    await helper.enableSemantics();

    console.log('[Test] Focusing search bar and typing query...');
    // Click on search bar area or input
    const input = await page.$('input');
    if (input) {
      await input.click();
      await input.fill('Coldplay');
      await page.keyboard.press('Enter');
    } else {
      // Fallback click on search bar coordinates
      await page.mouse.click(350, 48);
      await page.keyboard.type('Coldplay');
      await page.keyboard.press('Enter');
    }

    console.log('[Test] Waiting for search results to arrive...');
    await page.waitForTimeout(6000);
    await helper.screenshot('search_02_results');

    console.log('✓ 04_search.spec.js passed successfully');
    return { success: true };
  } catch (err) {
    console.error('✗ 04_search.spec.js failed:', err);
    await helper.screenshot('search_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runSearchTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runSearchTest };
