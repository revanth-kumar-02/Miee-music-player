const { BrowserHelper } = require('../helpers/browser_helper');

async function runPlaybackTest() {
  console.log('\n--- Running 05_playback.spec.js ---');
  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  try {
    console.log('[Test] Navigating to /home to start a real music track...');
    await helper.navigate('/home');
    await page.waitForTimeout(6000);
    await helper.enableSemantics();

    console.log('[Test] Triggering playback via Hero Play button or track card...');
    // Hero 'Play now' is located around (x: 230, y: 320)
    await page.mouse.click(230, 320);
    await page.waitForTimeout(3000);
    await helper.screenshot('playback_01_mini_player');

    console.log('[Test] Navigating to /player for full playback view...');
    await helper.navigate('/player');
    await page.waitForTimeout(4000);
    await helper.enableSemantics();
    await helper.screenshot('playback_02_expanded_player');

    console.log('[Test] Testing Play/Pause toggle...');
    await page.keyboard.press('Space');
    await page.waitForTimeout(1500);
    await helper.screenshot('playback_03_after_space_toggle');
    console.log('✓ 05_playback.spec.js passed successfully');
    return { success: true };
  } catch (err) {
    console.error('✗ 05_playback.spec.js failed:', err);
    await helper.screenshot('playback_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runPlaybackTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runPlaybackTest };
