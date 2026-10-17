const { BrowserHelper } = require('./helpers/browser_helper');

async function testCompleteUserFlow() {
  console.log('\n======================================================');
  console.log('Testing Complete User Flow: Register -> Onboarding -> Home');
  console.log('======================================================');

  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 });

  try {
    // Step 1: Navigate to /register
    console.log('[Step 1] Navigating to /register...');
    await helper.navigate('/register');
    await page.waitForTimeout(4000);
    await helper.enableSemantics();
    await helper.screenshot('flow_01_register_page');

    // Generate unique test email
    const timestamp = Date.now();
    const testEmail = `miee_listener_${timestamp}@testdomain.com`;
    console.log(`[Step 2] Filling registration form with email: ${testEmail}...`);

    const nameInput = await page.$('input[aria-label="Enter your name"]');
    const emailInput = await page.$('input[aria-label="Enter your email"]');
    const passwordInputs = await page.$$('input[type="password"]');

    if (nameInput) await nameInput.fill('Aria Montgomery');
    if (emailInput) await emailInput.fill(testEmail);
    if (passwordInputs.length >= 2) {
      await passwordInputs[0].fill('Sanctuary@2026');
      await passwordInputs[1].fill('Sanctuary@2026');
    }

    await helper.screenshot('flow_02_form_filled');

    // Click "Create Account"
    console.log('[Step 3] Submitting registration form...');
    const submitClicked = await page.evaluate(() => {
      const btn = Array.from(document.querySelectorAll('[role="button"]'))
        .find(e => (e.innerText || e.textContent || '').includes('Create Account'));
      if (btn) {
        btn.click();
        return true;
      }
      return false;
    });
    console.log('[Step 3] Submit clicked:', submitClicked);

    // Wait for Firebase Auth and Router redirection to /onboarding
    console.log('[Step 4] Waiting for auth completion and router redirect to /onboarding...');
    await page.waitForTimeout(6000);
    console.log('[Step 4] Current URL:', page.url());
    await helper.screenshot('flow_03_after_registration');

    // Step 5: Onboarding artist selection
    console.log('[Step 5] Onboarding page loaded. Enabling semantics...');
    await helper.enableSemantics();
    await page.waitForTimeout(2000);
    await helper.screenshot('flow_04_onboarding_artists');

    // Click 3 artists to satisfy the mandatory 3-5 artist requirement
    console.log('[Step 6] Selecting 3 favorite artists...');
    const artistsSelected = await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('[role="button"]'));
      // Filter out navigation or control buttons to find artist chips/cards
      const artistButtons = buttons.filter(b => {
        const txt = (b.innerText || b.textContent || '').trim();
        return txt.length > 2 && !txt.includes('Continue') && !txt.includes('Back') && !txt.includes('Search') && !txt.includes('Sign');
      });
      console.log('Found artist buttons:', artistButtons.length);
      let count = 0;
      for (const btn of artistButtons.slice(0, 3)) {
        btn.click();
        count++;
      }
      return count;
    });
    console.log(`[Step 6] Clicked ${artistsSelected} artist cards`);
    await page.waitForTimeout(2000);
    await helper.screenshot('flow_05_artists_selected');

    // Click Continue
    console.log('[Step 7] Clicking Continue to complete onboarding...');
    const continueClicked = await page.evaluate(() => {
      const btn = Array.from(document.querySelectorAll('[role="button"]'))
        .find(e => (e.innerText || e.textContent || '').includes('Continue'));
      if (btn) {
        btn.click();
        return true;
      }
      return false;
    });
    console.log('[Step 7] Continue clicked:', continueClicked);

    // Wait for redirect to /home and recommendation loading
    console.log('[Step 8] Waiting for redirect to /home...');
    await page.waitForTimeout(8000);
    console.log('[Step 8] Current URL:', page.url());
    await helper.screenshot('flow_06_home_loaded');

    console.log('======================================================');
    console.log('Complete User Flow test finished!');
    console.log('======================================================');
    return { success: true };
  } catch (err) {
    console.error('User flow error:', err);
    await helper.screenshot('flow_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  testCompleteUserFlow().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { testCompleteUserFlow };
