# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2026-02-12

### Added

- Support multiple communities in a single site (#284)
- Call for speakers feature (#324)
- Session proposals co-speaker invitation workflow (#338)
- Site stats page (#318)
- Pagination to some dashboard pages (#315)
- Share buttons in group/event pages (#311)
- Allow checking in attendees manually (#307)
- Group team now receives members notifications (#312)
- Validate images dimensions (#293)
- Option to redirect from previous hostnames (#291)

### Changed

- Allow bypassing session bounds check (#337)
- Allow updating all fields for past events (#328)
- Improve how notifications template data is stored (#258)
- Move attendees to event page (#304)
- Use community and group logos as default (#305)
- Only feature communities with content in home page (#302)
- Some database improvements (#333)
- Some improvements getting pending notifications (#257)
- Some improvements listing user groups (#303)
- Some UI improvements (#295, #308, #317, #320, #339)
- Upgrade dependencies and base images (#281, #319)

### Fixed

- Display inactive groups in community dashboard (#313)
- Capacity cannot be below current attendees count (#309)
- Events must have a start date to be published (#310)
- Fix issue in Helm chart (#290)
- Improve error deleting sponsor if used by events (#314)
- Preserve search query on events/groups toggle (#271)
- Show location on event page when coords missing (#256)

## [0.6.0] - 2025-12-18

### Added

- Event speakers notifications (#252)
- Justfile (#248, #250)
- Allow setting group and event coordinates (#245)
- Auto generate slugs for groups and events (#244)
- Zoom meetings integration (#236)

### Changed

- Hide map view on events search (#254)
- Improve location handling in community site (#253)
- Remove banner from event and group (#249)
- Improve management of groups and events location (#247)
- Improve input validation and integrity checks (#246)
- Upgrade dependencies and base images (#243)
- Some refactoring in database functions tests (#241)

### Fixed

- Users search should only return verified users (#251)

## [0.5.0] - 2025-12-01

### Added

- Initial version
