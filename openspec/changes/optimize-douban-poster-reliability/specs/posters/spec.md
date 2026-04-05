# Posters Specification Delta

## ADDED Requirements

### Requirement: Douban poster lookup reuses persisted query results

The poster pipeline shall persist Douban lookup outcomes so repeated lookups for the same normalized title do not require a fresh Douban request on every app launch.

#### Scenario: Repeated title lookup after relaunch

- **GIVEN** a title has already produced a Douban poster lookup outcome
- **WHEN** the app is relaunched and the same normalized title appears again
- **THEN** the app reuses the persisted lookup result when it is still valid
- **AND** it avoids a new Douban request unless the cache entry requires refresh

### Requirement: Douban throttling degrades gracefully

The poster pipeline shall detect unhealthy Douban behavior and suppress wasteful repeated retries before continuing to fallback providers.

#### Scenario: Douban becomes rate limited

- **GIVEN** Douban requests begin returning a throttling or equivalent failure outcome
- **WHEN** new posters need to be resolved
- **THEN** the app short-circuits repeated Douban retries for a suppression period
- **AND** it continues to fallback providers without waiting for the full old retry pattern

### Requirement: Douban traffic can use an optional internal proxy path

The app shall support optional internal proxy-based routing for Douban search or image requests without requiring a user-facing configuration entry.

#### Scenario: Internal proxy configured

- **GIVEN** an internal Douban proxy endpoint is configured
- **WHEN** the app issues Douban search or image requests
- **THEN** the app routes those requests through the configured proxy path

#### Scenario: Internal proxy not configured

- **GIVEN** no internal Douban proxy endpoint is configured
- **WHEN** the app issues Douban search or image requests
- **THEN** the app keeps using direct networking behavior
- **AND** the proxy feature remains inactive
