#!/bin/bash

# Define the base Firefox directory
BASE_DIR="$HOME/.mozilla/firefox"

if [ ! -d "$BASE_DIR" ]; then
  echo "Error: Firefox directory not found at $BASE_DIR"

  exit 1
fi

# Find all directories containing a prefs.js (actual profile folders)
PROFILES=$(find "$BASE_DIR" -maxdepth 2 -name "prefs.js" -exec dirname {} \;)

if [ -z "$PROFILES" ]; then
  echo "Error: No Firefox profiles found."
  exit 1
fi

for PROFILE in $PROFILES; do
  echo "Applying privacy hardening to: $PROFILE"

  cat <<EOF >"$PROFILE/user.js"
/** * SILENT FIREFOX CONFIG
 * Purpose: Zero telemetry, zero background pings, keeps DRM functional.
 */

// --- SECTION 1: TELEMETRY & DATA COLLECTION ---
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.server", "data:,");
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");

// --- SECTION 2: NETWORK QUIET (STOP SPECUATIVE PINGS) ---
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.predictor.enable-prefetch", false);
user_pref("browser.places.speculativeConnect.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("browser.aboutConfig.showWarning", false);


// --- SECTION 3: CONNECTIVITY CHECKS (FIREFOX HOME PINGS) ---
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);

// --- SECTION 4: GOOGLE SAFE BROWSING (TRADEOFF: PRIVACY VS MALWARE PROTECTION) ---
// Disabling these stops pings to Google servers for URL checking
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.remote.enabled", false);

// --- SECTION 5: SEARCH & URLBAR (STOP LEAKING KEYSTROKES) ---
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
user_pref("browser.urlbar.dnsResolveSingleWordsAfterSearch", 0);

// --- SECTION 6: UI CLEANUP & BLOAT ---
user_pref("extensions.pocket.enabled", false);
user_pref("browser.shopping.experience2023.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.discovery.enabled", false);

// --- SECTION 7: KEEP DRM ENABLED (NETFLIX/SPOTIFY) ---
user_pref("media.eme.enabled", true);
user_pref("browser.eme.ui.enabled", true);
EOF

done

echo "-------------------------------------------------------"
echo "Success: user.js written to all found profiles."
echo "Note: If you are on Linux, ensure you update Firefox via"
echo "your package manager, as auto-update pings are minimized."
echo "-------------------------------------------------------"
