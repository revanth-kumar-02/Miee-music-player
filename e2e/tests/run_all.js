const { runAuthTest } = require('./01_auth.spec');
const { runOnboardingTest } = require('./02_onboarding.spec');
const { runHomeDiscoveryTest } = require('./03_home_discovery.spec');
const { runSearchTest } = require('./04_search.spec');
const { runPlaybackTest } = require('./05_playback.spec');
const { runLibraryTest } = require('./06_library_playlists.spec');
const { runResponsiveTest } = require('./07_responsive.spec');

async function main() {
  console.log('====================================================');
  console.log('Starting Miee Autonomous Playwright E2E Suite');
  console.log('Target Server: http://127.0.0.1:8080');
  console.log('====================================================');

  const summary = [];

  const suites = [
    { name: '01_auth', runner: runAuthTest },
    { name: '02_onboarding', runner: runOnboardingTest },
    { name: '03_home_discovery', runner: runHomeDiscoveryTest },
    { name: '04_search', runner: runSearchTest },
    { name: '05_playback', runner: runPlaybackTest },
    { name: '06_library_playlists', runner: runLibraryTest },
    { name: '07_responsive', runner: runResponsiveTest },
  ];

  for (const suite of suites) {
    try {
      const res = await suite.runner();
      summary.push({ name: suite.name, status: res.success ? 'PASSED' : 'FAILED', error: res.error || null });
    } catch (e) {
      summary.push({ name: suite.name, status: 'FAILED', error: e.message });
    }
  }

  console.log('\n====================================================');
  console.log('Miee E2E Test Suite Results Summary:');
  console.log('====================================================');
  let failures = 0;
  for (const item of summary) {
    console.log(`- ${item.name.padEnd(25)} : [${item.status}] ${item.error ? '(' + item.error + ')' : ''}`);
    if (item.status === 'FAILED') failures++;
  }
  console.log('====================================================\n');

  if (failures > 0) {
    console.error(`Total failures: ${failures}`);
    process.exit(1);
  } else {
    console.log('All 7 E2E test suites passed successfully!');
    process.exit(0);
  }
}

main().catch(err => {
  console.error('Fatal runner error:', err);
  process.exit(1);
});
