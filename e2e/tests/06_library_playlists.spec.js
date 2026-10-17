const { BrowserHelper } = require('../helpers/browser_helper');

async function runLibraryTest() {
  console.log('\n--- Running 06_library_playlists.spec.js ---');
  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  try {
    // 1. Playlists page
    console.log('[Test] Navigating to /playlists...');
    await helper.navigate('/playlists');
    await page.waitForTimeout(4000);
    await helper.screenshot('library_01_playlists');

    await helper.enableSemantics();

    // 2. Liked songs page
    console.log('[Test] Navigating to /liked-songs...');
    await helper.navigate('/liked-songs');
    await page.waitForTimeout(4000);
    await helper.screenshot('library_02_liked_songs');

    console.log('✓ 06_library_playlists.spec.js passed successfully');
    return { success: true };
  } catch (err) {
    console.error('✗ 06_library_playlists.spec.js failed:', err);
    await helper.screenshot('library_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runLibraryTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runLibraryTest };
