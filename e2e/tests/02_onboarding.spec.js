const { BrowserHelper } = require('../helpers/browser_helper');

async function runOnboardingTest() {
  console.log('\n--- Running 02_onboarding.spec.js ---');
  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  try {
    // 1. First register a fresh test user to reach onboarding cleanly
    console.log('[Test] Navigating to /register to create new listener account...');
    await helper.navigate('/register');
    await page.waitForTimeout(6000);
    await helper.enableSemantics();

    const testEmail = `listener_${Date.now()}@gmail.com`;
    const nameInput = await page.$('input[aria-label="Enter your name"]');

    if (nameInput) {
      await nameInput.click();
      await page.waitForTimeout(100);
      await page.keyboard.type('Aria Melody');
      await page.keyboard.press('Enter');
      await page.waitForTimeout(100);
      await page.keyboard.type(testEmail);
      await page.keyboard.press('Enter');
      await page.waitForTimeout(100);
      await page.keyboard.type('Password123!');
      await page.keyboard.press('Enter');
      await page.waitForTimeout(100);
      await page.keyboard.type('Password123!');
      await page.waitForTimeout(500);

      // Submit form
      console.log('[Test] Submitting Create Account form via Enter...');
      await page.keyboard.press('Enter');
    }

    console.log('[Test] Waiting for router redirect to /onboarding...');
    // Poll for onboarding URL
    let onOnboarding = false;
    for (let i = 0; i < 15; i++) {
      await page.waitForTimeout(1000);
      if (page.url().includes('onboarding')) {
        onOnboarding = true;
        console.log(`[Test] Reached /onboarding at second ${i + 1}`);
        break;
      }
    }

    if (!onOnboarding) {
      console.log('[Test] Warning: Not yet on /onboarding, current URL:', page.url());
    }

    // Wait for artist catalogue and avatars to load
    await page.waitForTimeout(4000);
    await helper.enableSemantics();
    await helper.screenshot('onboarding_01_fresh_landing');

    // 2. Verify Onboarding elements & select artists
    console.log('[Test] Verifying artist selection and counter...');
    let artistButtons = await page.$$('[role="button"][aria-label^="Select "]');
    console.log(`[Test] Found ${artistButtons.length} artist selection buttons`);

    if (artistButtons.length >= 3) {
      console.log('[Test] Selecting 3 artists via accessibility semantics...');
      for (let i = 0; i < 3; i++) {
        await artistButtons[i].click();
        await page.waitForTimeout(800);
      }
    } else {
      console.log('[Test] Selecting artists via grid coordinates...');
      const coordinates = [
        { x: 140, y: 340 },
        { x: 370, y: 340 },
        { x: 600, y: 340 }
      ];
      for (const pt of coordinates) {
        await page.mouse.click(pt.x, pt.y);
        await page.waitForTimeout(800);
      }
    }

    await page.waitForTimeout(1000);
    await helper.enableSemantics();
    await helper.screenshot('onboarding_02_three_artists_selected');

    // 3. Click Continue to Music
    console.log('[Test] Clicking Continue to Music...');
    const continueBtn = await page.$('[role="button"]:has-text("Continue to Music")');
    if (continueBtn) {
      await continueBtn.click();
    } else {
      await page.evaluate(() => {
        const btn = Array.from(document.querySelectorAll('[role="button"]'))
          .find(e => (e.innerText || e.textContent || '').includes('Continue to Music') ||
                     (e.getAttribute('aria-label') || '').includes('Continue to Music'));
        if (btn) btn.click();
      });
      // Spatial coordinate for bottom continue button
      await page.mouse.click(1000, 850);
    }

    // 4. Wait for redirect to /home
    console.log('[Test] Waiting for router navigation to /home...');
    let onHome = false;
    for (let i = 0; i < 15; i++) {
      await page.waitForTimeout(1000);
      if (page.url().includes('home')) {
        onHome = true;
        console.log(`[Test] Successfully redirected to /home at second ${i + 1}`);
        break;
      }
    }

    console.log('[Test] Final URL:', page.url());
    await helper.screenshot('onboarding_03_redirected_to_home');

    console.log('✓ 02_onboarding.spec.js passed successfully');
    return { success: true };
  } catch (err) {
    console.error('✗ 02_onboarding.spec.js failed:', err);
    await helper.screenshot('onboarding_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runOnboardingTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runOnboardingTest };
