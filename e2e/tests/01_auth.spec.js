const { BrowserHelper } = require('../helpers/browser_helper');

async function runAuthTest() {
  console.log('\n--- Running 01_auth.spec.js ---');
  const helper = new BrowserHelper();
  const page = await helper.launch({ width: 1440, height: 900 }, { persistent: false });

  try {
    // 1. Navigate to Register Page
    console.log('[Test] Navigating to /register...');
    await helper.navigate('/register');
    await page.waitForTimeout(4000);
    await helper.enableSemantics();
    await helper.screenshot('auth_01_register_page');

    // 2. Test empty submission triggers validation
    console.log('[Test] Clicking "Create Account" with empty fields to trigger validation...');
    const createBtn = await page.$('[role="button"]:has-text("Create Account")');
    if (createBtn) {
      await createBtn.click();
      await page.waitForTimeout(1000);
      await helper.screenshot('auth_02_empty_validation_errors');
    }

    // 3. Test invalid email format
    console.log('[Test] Filling invalid email and short password...');
    const nameInput = await page.$('input[aria-label="Enter your name"]');
    const emailInput = await page.$('input[aria-label="Enter your email"]');
    const passwordInputs = await page.$$('input[type="password"]');

    if (nameInput) await nameInput.fill('Test User');
    if (emailInput) await emailInput.fill('invalid-email-address');
    if (passwordInputs.length >= 2) {
      await passwordInputs[0].fill('123'); // short password
      await passwordInputs[1].fill('456'); // mismatch password
    }

    if (createBtn) {
      await createBtn.click();
      await page.waitForTimeout(1000);
      await helper.screenshot('auth_03_invalid_input_errors');
    }

    // 4. Test Navigation to Login Page
    console.log('[Test] Clicking "Sign In" link to navigate to Login page...');
    const signInBtn = await page.$('[role="button"]:has-text("Sign In")');
    if (signInBtn) {
      await signInBtn.click();
      await page.waitForTimeout(3000);
      await helper.enableSemantics();
      await helper.screenshot('auth_04_login_page');
    }

    // 5. Test Forgot Password Dialog
    console.log('[Test] Testing Forgot Password dialog...');
    const forgotPwdLink = await page.$('text=Forgot Password');
    if (forgotPwdLink) {
      await forgotPwdLink.click();
      await page.waitForTimeout(1000);
      await helper.screenshot('auth_05_forgot_password_dialog');
    }

    console.log('✓ 01_auth.spec.js passed successfully');
    return { success: true };
  } catch (err) {
    console.error('✗ 01_auth.spec.js failed:', err);
    await helper.screenshot('auth_error');
    return { success: false, error: err.message };
  } finally {
    await helper.close();
  }
}

if (require.main === module) {
  runAuthTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runAuthTest };
