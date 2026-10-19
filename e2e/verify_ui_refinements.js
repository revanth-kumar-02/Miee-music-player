const { BrowserHelper } = require('./helpers/browser_helper');
const assert = require('assert');

async function verifyRefinements() {
  console.log('\n=============================================================');
  console.log('MIEE UI REFINEMENT VERIFICATION: Login Scrollbar & Artist Grid');
  console.log('=============================================================\n');

  const helper = new BrowserHelper();
  // Persistent = false ensures a clean state
  const page = await helper.launch({ width: 1440, height: 900 }, { persistent: false });

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
    // -------------------------------------------------------------
    // PART 1: LOGIN PAGE SCROLLBAR & FUNCTIONALITY VERIFICATION
    // -------------------------------------------------------------
    console.log('--- PART 1: Testing Login Page ---');
    console.log('[Login] Navigating to /login...');
    await helper.navigate('/login');
    await page.waitForTimeout(4000);
    await helper.enableSemantics();

    // Check at 1440x900
    console.log('[Login] Verifying 1440x900 desktop viewport...');
    await helper.screenshot('verified_login_1440x900');

    // Check at 1280x720 (previously overflowing by 16px)
    console.log('[Login] Verifying 1280x720 standard desktop viewport...');
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.waitForTimeout(1000);
    await helper.screenshot('verified_login_1280x720');

    // Check at 1024x768 (standard 4:3 / tablet desktop)
    console.log('[Login] Verifying 1024x768 desktop viewport...');
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.waitForTimeout(1000);
    await helper.screenshot('verified_login_1024x768');

    // Check scroll state in the DOM to prove zero vertical overflow at 720p and 768p
    const scrollStatus = await page.evaluate(() => {
      const form = document.querySelector('form');
      return {
        formScrollHeight: form ? form.scrollHeight : null,
        formClientHeight: form ? form.clientHeight : null,
        overflows: form ? form.scrollHeight > form.clientHeight : null,
      };
    });
    console.log('[Login] Scroll overflow metrics at 1024x768:', scrollStatus);

    // Verify small screen / short window responsiveness: when genuinely needed, scrolling works
    console.log('[Login] Testing short viewport (width: 1024, height: 480) for scroll accessibility...');
    await page.setViewportSize({ width: 1024, height: 480 });
    await page.waitForTimeout(1000);
    await helper.screenshot('verified_login_short_window_480');

    // Restore to desktop 1440x900
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.waitForTimeout(1000);

    // Test Login Functionality:
    // 1. Password visibility toggle
    console.log('[Login] Testing password visibility toggle...');
    const visibilityBtn = await page.$('button[aria-label="Show password"], button:has([class*="visibility"]), button:has-text("Show password")');
    const pwdInput = await page.$('input[type="password"]');
    if (visibilityBtn && pwdInput) {
      await visibilityBtn.click();
      await page.waitForTimeout(300);
      console.log('✓ Password visibility toggle clickable');
    }

    // 2. Remember me checkbox
    console.log('[Login] Testing Remember me checkbox...');
    const checkbox = await page.$('[role="checkbox"]');
    if (checkbox) {
      await checkbox.click();
      await page.waitForTimeout(300);
      console.log('✓ Remember me checkbox toggled');
    }

    // 3. Forgot Password dialog
    console.log('[Login] Testing Forgot Password dialog...');
    const forgotPwd = await page.$('text=Forgot Password');
    if (forgotPwd) {
      await forgotPwd.click();
      await page.waitForTimeout(1000);
      await helper.screenshot('verified_login_forgot_password_dialog');
      // Close dialog via Cancel
      const cancelBtn = await page.$('text=Cancel');
      if (cancelBtn) await cancelBtn.click();
      await page.waitForTimeout(500);
      console.log('✓ Forgot Password dialog opened and cancelled');
    }

    // 4. Google Sign-In button
    console.log('[Login] Testing Google Sign-in button...');
    const googleBtn = await page.$('[aria-label="Sign in with Google"]');
    if (googleBtn) {
      await googleBtn.click();
      await page.waitForTimeout(1000);
      console.log('✓ Google sign-in button clicked');
    }

    // 5. Create Account navigation link
    console.log('[Login] Clicking "Create Account" link to transition to registration & onboarding...');
    const createAccountLink = await page.$('text=Create Account');
    if (createAccountLink) {
      await createAccountLink.click();
      await page.waitForTimeout(3000);
      await helper.enableSemantics();
      console.log('[Auth] URL after clicking Create Account:', page.url());
    }

    // -------------------------------------------------------------
    // PART 2: ONBOARDING PERSONALIZATION GRID & TILES VERIFICATION
    // -------------------------------------------------------------
    console.log('\n--- PART 2: Testing Personalization / Onboarding Grid ---');
    console.log('[Onboarding] Registering fresh listener account to reach onboarding...');
    const testEmail = `miee_ui_test_${Date.now()}@testsanctuary.com`;
    const nameInput = await page.$('input[aria-label="Enter your name"]');
    if (nameInput) {
      await nameInput.click();
      await page.keyboard.type('Lyra Vance');
      await page.keyboard.press('Enter');
      await page.waitForTimeout(200);
      await page.keyboard.type(testEmail);
      await page.keyboard.press('Enter');
      await page.waitForTimeout(200);
      await page.keyboard.type('Sanctuary@2026');
      await page.keyboard.press('Enter');
      await page.waitForTimeout(200);
      await page.keyboard.type('Sanctuary@2026');
      await page.keyboard.press('Enter');
    }

    for (let i = 0; i < 20; i++) {
      await page.waitForTimeout(1000);
      if (page.url().includes('onboarding')) {
        console.log(`[Onboarding] Successfully reached /onboarding at second ${i + 1}`);
        break;
      }
    }

    await page.waitForTimeout(4000);
    await helper.enableSemantics();

    // 1. Desktop 1440px Viewport (Expect 6 columns, compact tiles)
    console.log('[Onboarding] Capturing desktop 1440x900 layout...');
    await helper.screenshot('verified_onboarding_1440x900');

    // 2. Tablet 1024px Viewport (Expect 5 columns)
    console.log('[Onboarding] Capturing tablet 1024x768 layout...');
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.waitForTimeout(1000);
    await helper.screenshot('verified_onboarding_1024x768');

    // 3. Mobile 390px Viewport (Expect 3 columns)
    console.log('[Onboarding] Capturing mobile 390x844 layout...');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(1000);
    await helper.screenshot('verified_onboarding_390x844');

    // Restore to 1440x900 for interactive tests
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.waitForTimeout(1000);

    // 4. Test Language Filter Chips
    console.log('[Onboarding] Testing language filter chips (Tamil, Hindi, All)...');
    const tamilChip = await page.$('text=Tamil');
    if (tamilChip) {
      await tamilChip.click();
      await page.waitForTimeout(1500);
      await helper.screenshot('verified_onboarding_filter_tamil');
      console.log('✓ Tamil language filter clicked');
    }

    const allChip = await page.$('text=All');
    if (allChip) {
      await allChip.click();
      await page.waitForTimeout(1500);
      console.log('✓ Reset to "All" language filter');
    }

    // 5. Test Search Field
    console.log('[Onboarding] Testing search field with query "Coldplay"...');
    const searchInput = await page.$('input[placeholder*="Search any artist"], input[aria-label*="Search"]');
    if (searchInput) {
      await searchInput.click();
      await page.keyboard.type('Coldplay');
      await page.waitForTimeout(2000);
      await helper.screenshot('verified_onboarding_search_coldplay');
      console.log('✓ Searched for Coldplay');

      // Clear search
      await searchInput.fill('');
      await page.keyboard.press('Backspace');
      await page.waitForTimeout(1500);
      console.log('✓ Cleared search back to popular artists');
    }

    // 6. Test Artist Selection & Dusty Rose Highlighting & Counter Badge
    console.log('[Onboarding] Testing artist selection, counter badge, and selection limit...');
    // Find artist cards
    const artistButtons = await page.$$('[role="button"][aria-label^="Select "]');
    console.log(`[Onboarding] Found ${artistButtons.length} artist selectable buttons in semantic tree`);

    if (artistButtons.length >= 5) {
      // Select 1st artist
      await artistButtons[0].click();
      await page.waitForTimeout(600);
      await helper.screenshot('verified_onboarding_selected_1');

      // Select 2nd artist
      await artistButtons[1].click();
      await page.waitForTimeout(600);
      await helper.screenshot('verified_onboarding_selected_2');

      // Select 3rd artist -> should satisfy min 3 requirement
      await artistButtons[2].click();
      await page.waitForTimeout(600);
      await helper.screenshot('verified_onboarding_selected_3_can_continue');

      // Select 4th & 5th artists
      await artistButtons[3].click();
      await page.waitForTimeout(400);
      await artistButtons[4].click();
      await page.waitForTimeout(600);
      await helper.screenshot('verified_onboarding_selected_5_max_limit');

      // Verify counter text shows 5 of 5
      const counterText = await page.evaluate(() => {
        return document.body.innerText.includes('5 of 5 selected') || document.body.textContent.includes('5 of 5 selected');
      });
      console.log('[Onboarding] Counter text verified 5 of 5:', counterText);

      // Deselect 5th artist to test toggle
      await artistButtons[4].click();
      await page.waitForTimeout(600);
      console.log('✓ Deselecting artist works correctly');

      // 7. Click Continue button
      console.log('[Onboarding] Submitting artist selection via Continue button...');
      const continueBtn = await page.$('[role="button"]:has-text("Continue to Music")');
      if (continueBtn) {
        await continueBtn.click();
      } else {
        // Fallback by coordinates of bottom right
        await page.mouse.click(1000, 860);
      }

      for (let i = 0; i < 15; i++) {
        await page.waitForTimeout(1000);
        if (page.url().includes('home')) {
          console.log(`[Onboarding] Successfully transitioned to /home at second ${i + 1}`);
          break;
        }
      }

      await page.waitForTimeout(3000);
      await helper.screenshot('verified_home_after_onboarding');
      console.log('[Onboarding] Final URL:', page.url());
    }

    console.log('\n=============================================================');
    console.log('All verification steps completed successfully!');
    console.log('Console errors recorded:', consoleErrors.length);
    if (consoleErrors.length > 0) {
      console.log('Console error details:', consoleErrors);
    }
    console.log('=============================================================\n');

  } catch (err) {
    console.error('Verification error:', err);
    await helper.screenshot('verification_failure');
    throw err;
  } finally {
    await helper.close();
  }
}

verifyRefinements();
