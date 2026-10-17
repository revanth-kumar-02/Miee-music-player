const { BrowserHelper } = require('../helpers/browser_helper');

async function runResponsiveTest() {
  console.log('\n--- Running 07_responsive.spec.js ---');
  const breakpoints = [
    { name: 'desktop', width: 1440, height: 900 },
    { name: 'compact_desktop', width: 1024, height: 768 },
    { name: 'mobile', width: 390, height: 844 },
  ];

  const results = {};

  for (const bp of breakpoints) {
    console.log(`[Test] Testing viewport: ${bp.name} (${bp.width}x${bp.height})...`);
    const helper = new BrowserHelper();
    const page = await helper.launch({ width: bp.width, height: bp.height });

    try {
      await helper.navigate('/home');
      await page.waitForTimeout(5000);
      const shot = await helper.screenshot(`responsive_${bp.name}_home`);
      console.log(`[Test] Saved ${shot}`);
      results[bp.name] = true;
    } catch (err) {
      console.error(`[Test] Error on ${bp.name}:`, err);
      results[bp.name] = false;
    } finally {
      await helper.close();
    }
  }

  const allPassed = Object.values(results).every(Boolean);
  console.log(allPassed ? '✓ 07_responsive.spec.js passed successfully' : '✗ 07_responsive.spec.js had failures');
  return { success: allPassed, details: results };
}

if (require.main === module) {
  runResponsiveTest().then(res => process.exit(res.success ? 0 : 1));
}

module.exports = { runResponsiveTest };
