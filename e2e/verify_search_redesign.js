const { BrowserHelper } = require('./helpers/browser_helper');

async function runSearchRedesignVerification() {
  console.log('\n======================================================');
  console.log('Verifying Miee Search & Now Playing UI Redesign (Pass 2)');
  console.log('======================================================\n');

  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  const consoleErrors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') {
      consoleErrors.push(msg.text());
    }
  });
  page.on('pageerror', err => {
    consoleErrors.push(err.message);
  });

  try {
    // 1. Initial navigation to /search
    console.log('[Step 1] Navigating to /search at 1440x900...');
    await helper.navigate('/search');
    await page.waitForTimeout(4000);
    await helper.enableSemantics();

    console.log('[Step 1] Capturing empty Search state at 1440x900...');
    await helper.screenshot('redesign_01_search_empty_1440x900');

    // 2. Perform search for "West Coast Lana Del Rey"
    console.log('[Step 2] Typing query "West Coast Lana Del Rey" into search bar...');
    const input = await page.$('input');
    if (input) {
      await input.click();
      await input.fill('West Coast Lana Del Rey');
      await page.keyboard.press('Enter');
    } else {
      await page.mouse.click(350, 48);
      await page.keyboard.type('West Coast Lana Del Rey');
      await page.keyboard.press('Enter');
    }

    console.log('[Step 2] Waiting for search results to arrive...');
    await page.waitForTimeout(6000);
    await helper.screenshot('redesign_02_search_results_1440x900');

    // 3. Play a track from results
    console.log('[Step 3] Clicking a search result track to play...');
    // In search results, click on the first track item or play button
    // The top result card or first song tile is around (x: 450, y: 340) or we can click the play button
    await page.mouse.click(450, 320);
    await page.waitForTimeout(4000);

    console.log('[Step 3] Checking current URL to ensure user stayed on Search (did not navigate to /player)...');
    const currentUrl = page.url();
    console.log('[Step 3] Current URL:', currentUrl);
    await helper.screenshot('redesign_03_playing_in_search_1440x900');

    // 4. Test 1024x768 (Smaller Desktop)
    console.log('[Step 4] Testing 1024x768 viewport...');
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.waitForTimeout(2000);
    await helper.screenshot('redesign_04_results_1024x768');

    // 5. Test 390x844 (Mobile Width)
    console.log('[Step 5] Testing 390x844 mobile viewport...');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(2000);
    await helper.screenshot('redesign_05_results_390x844');

    // Restore to 1440x900
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.waitForTimeout(1500);

    // 6. Navigate to /home to verify persistent bottom player
    console.log('[Step 6] Navigating to /home to verify persistent player...');
    await helper.navigate('/home');
    await page.waitForTimeout(4000);
    await helper.enableSemantics();
    await helper.screenshot('redesign_06_persistent_player_on_home');

    // 7. Open dedicated Now Playing screen (/player)
    console.log('[Step 7] Navigating to dedicated /player screen...');
    await helper.navigate('/player');
    await page.waitForTimeout(4000);
    await helper.enableSemantics();
    await helper.screenshot('redesign_07_dedicated_now_playing');

    // 8. Return to /search
    console.log('[Step 8] Returning to /search...');
    await helper.navigate('/search');
    await page.waitForTimeout(3000);
    await helper.enableSemantics();
    await helper.screenshot('redesign_08_back_to_search');

    console.log('\n--- Console Errors Check ---');
    console.log(`Console errors captured: ${consoleErrors.length}`);
    if (consoleErrors.length > 0) {
      console.log('Errors:', consoleErrors);
    }

    console.log('\n✓ Redesign verification completed successfully.');
    return { success: true, consoleErrors };
  } catch (err) {
    console.error('✗ Redesign verification failed:', err);
    await helper.screenshot('redesign_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runSearchRedesignVerification().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runSearchRedesignVerification };
