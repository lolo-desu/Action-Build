# vrcrp Native · 2.0 preview

SwiftUI third-party client for erp.sex. Minimum iOS 26; compatible with iOS 27. Uses the system tab bar, navigation, lists, forms, sheets, menus, text fields, photo picker and a Liquid Glass send button. The monochrome icon and the existing bundle identifier are retained.

## Feature coverage

| Feature | Implementation |
| --- | --- |
| Explore, browse, likes received/sent, visitors | Native lists, profiles and pagination |
| Profile details and basic name/tagline/bio editing | Native |
| Profile reactions, advanced filters, models, tags, full metadata | Website sheet |
| Match list and chat | Native |
| Text messages, read acknowledgements, recall, translate, boundary acknowledgement, close match, VRChat share | Native API requests |
| Photo selection/upload and voice recording/upload/playback | Native; ordinary/suggestive upload ratings, full rating options in website sheet |
| Message history | Native protected local cache plus server history; existing browser-local history remains accessible in website sheet |
| Posts, search, sorting, detail, likes and comments | Native |
| Post creation/editing, complex reactions and moderation/report dialogs | Website sheet |
| Notifications and marking all read | Native; full event details in website sheet |
| Local chat notifications | Native, while the client is running |
| Account security, VRChat account services, energy, membership, invitations, detailed privacy/settings | Website sheet |
| Login, registration, captcha, OAuth and account onboarding | Website sheet, with shared site cookies |
| All remaining website functionality | Full website entry under My account |

This is a native preview, not a complete native reimplementation of every website screen. No original site content or user records are bundled as fixtures; the preview uses invented, ordinary test data.

## Sessions and data

Requests go directly to https://erp.sex/api/v1 and wss://erp.sex/api/v1/ws. The app does not use a custom relay or collect passwords. Login takes place on the original website. WKWebView cookies are copied to the native URLSession cookie store; CSRF and content-mode headers match the website client. Updated cookies are copied back to the website store.

Local native message history is stored per account and match with complete iOS file protection. Earlier history already stored by the previous web wrapper stays in the browser's persistent store; it is not automatically imported into the native cache. Keep the same signing identity/bundle identifier and install as an update to retain the app's container. Uninstalling the old app removes its local history.

The site has Web Push but this client has no APNs registration/backend. Background or terminated-app notifications are not guaranteed. No background-mode workaround is declared.

## Build and validation

GitHub Actions branch `vrcrp-native-ios` builds with the macOS 26/Xcode runner:

```sh
bash scripts/build.sh
```

Output: `build/vrcrp-native-unsigned.ipa`. No developer certificate is needed for building; use your own signing/install tooling.

Core fixture tests check JSON decoding, wrapped-user IDs, message merging, recalls, deduplication, text round trips and dates. The device IPA is checked for arm64 architecture, no code signature and ZIP integrity.

Authenticated site operations, OAuth, device recording/upload support and iOS 27 keyboard behavior have not been verified with a real user account/device. Server permissions, membership limits and content restrictions are always enforced by the original server. The existing website client is the observed API contract; changes by the site can require client updates.
