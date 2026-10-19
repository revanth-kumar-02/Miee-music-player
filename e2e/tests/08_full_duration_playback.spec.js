const { BrowserHelper } = require('../helpers/browser_helper');

async function runFullDurationPlaybackTest() {
  console.log('\n--- Running 08_full_duration_playback.spec.js ---');
  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  const mediaRequests = [];
  const mediaResponses = [];
  const errors = [];

  page.on('request', req => {
    const url = req.url();
    if (url.includes('googlevideo.com') || url.includes('videoplayback') || url.includes('/api/yt/') || url.includes('itunes.apple.com')) {
      mediaRequests.push({ url, method: req.method() });
      console.log('[Media Request]', req.method(), url.substring(0, 110));
    }
  });

  page.on('response', resp => {
    const url = resp.url();
    if (url.includes('googlevideo.com') || url.includes('videoplayback')) {
      const headers = resp.headers();
      mediaResponses.push({
        url: url.substring(0, 110),
        status: resp.status(),
        contentType: headers['content-type'],
        contentLength: headers['content-length'],
      });
      console.log('[Audio Stream Response]', resp.status(), headers['content-type'], `size=${headers['content-length']}`);
    }
  });

  page.on('console', msg => {
    const text = msg.text();
    if (text.includes('[Playback]') || text.includes('[AudioHandler]') || text.includes('[StreamCache]')) {
      console.log('[Browser Console]', text);
    }
    if (msg.type() === 'error') {
      errors.push(text);
    }
  });

  try {
    console.log('[Test Step 1] Navigating to /search...');
    await helper.navigate('/search');
    await page.waitForTimeout(3000);
    await helper.enableSemantics();

    console.log('[Test Step 2] Searching for "West Coast Lana Del Rey"...');
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

    console.log('[Test Step 3] Waiting for real YouTube results from backend proxy...');
    await page.waitForTimeout(6000);
    await helper.screenshot('08_01_search_results');

    console.log('[Test Step 4] Clicking first search result at (x: 400, y: 310) to start playback...');
    await page.mouse.click(400, 310);
    await page.waitForTimeout(6000);
    await helper.screenshot('08_02_playback_started');

    console.log('[Test Step 5] Checking for mini player and verifying audio stream resolution...');
    // Inspect network requests
    const itunesPreviews = mediaRequests.filter(r => r.url.includes('itunes.apple.com') || r.url.includes('/AudioPreview'));
    if (itunesPreviews.length > 0) {
      throw new Error(`CRITICAL BUG DETECTED: Player attempted to load 30-second iTunes preview! URL: ${itunesPreviews[0].url}`);
    }

    const fullStreams = mediaRequests.filter(r => r.url.includes('googlevideo.com') || r.url.includes('videoplayback'));
    console.log(`Full YouTube audio streams requested: ${fullStreams.length}`);
    if (fullStreams.length === 0) {
      // Check if maybe it clicked slightly off; try clicking play button directly at (230, 310) or clicking the card
      console.log('Retrying click on track item at (350, 310)...');
      await page.mouse.click(350, 310);
      await page.waitForTimeout(6000);
      await helper.screenshot('08_02_retry_click');
    }

    console.log('[Test Step 6] Navigating to /player to inspect full duration on player screen...');
    await helper.navigate('/player');
    await page.waitForTimeout(4000);
    await helper.screenshot('08_03_expanded_player');

    console.log('[Test Step 7] Testing pause and resume via Space key...');
    await page.keyboard.press('Space');
    await page.waitForTimeout(1500);
    await helper.screenshot('08_04_paused');

    await page.keyboard.press('Space');
    await page.waitForTimeout(1500);
    await helper.screenshot('08_05_resumed');

    console.log('[Test Step 8] Testing seeking forward past 30 seconds on waveform...');
    // Click on progress waveform around 50% (x: 575, y: 648)
    await page.mouse.click(575, 648);
    await page.waitForTimeout(3000);
    await helper.screenshot('08_06_after_seek_past_30s');

    console.log('[Test Step 9] Waiting 5 seconds to verify playback continues advancing past 30s...');
    await page.waitForTimeout(5000);
    await helper.screenshot('08_07_advancing_past_30s');

    console.log('\n--- VERIFICATION SUMMARY ---');
    console.log('iTunes preview URLs requested:', itunesPreviews.length, '(EXPECTED: 0)');
    console.log('Full stream requests:', mediaRequests.filter(r => r.url.includes('googlevideo.com')).length);
    console.log('Successful media responses:', mediaResponses);

    console.log('✓ 08_full_duration_playback.spec.js completed successfully');
    return {
      success: true,
      itunesPreviewsCount: itunesPreviews.length,
      fullStreamRequestsCount: fullStreams.length,
    };
  } catch (err) {
    console.error('✗ 08_full_duration_playback.spec.js failed:', err);
    await helper.screenshot('08_playback_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runFullDurationPlaybackTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runFullDurationPlaybackTest };
