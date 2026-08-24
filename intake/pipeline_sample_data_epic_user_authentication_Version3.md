# Epic: User Authentication

Users must be able to securely register, log in, and manage their credentials
within the banking application.

## Requirements

### REQ-001: User Registration

Users must be able to create a new bank account profile using their full legal
name, date of birth, SSN (last 4 digits), email address, and a chosen password.

- [ ] Registration form validates all required fields before submission
- [ ] SSN last 4 digits are masked after entry
- [ ] Duplicate email addresses are rejected with a clear error message
- [ ] Confirmation email is sent upon successful registration

**Requirement Type:** Functional
**NFR Category:** N/A
**Priority:** P0
**Story Points:** 5
**Source:** Project kickoff meeting - 2026-08-01
**Clarification Status:** Confirmed
**Confidence:** Firm

---

### REQ-002: Multi-Factor Authentication (MFA)

All users must be required to complete MFA via SMS or authenticator app when
logging in from an unrecognized device.

- [ ] User is prompted for MFA code after entering valid credentials on new device
- [ ] SMS and authenticator app (TOTP) are both supported
- [ ] MFA code expires after 5 minutes
- [ ] User can manage trusted devices from account settings

**Requirement Type:** Functional
**NFR Category:** N/A
**Priority:** P0
**Story Points:** 8
**Source:** Security requirements doc - v1.2 - 2026-08-03
**Clarification Status:** Confirmed
**Confidence:** Firm

---

### REQ-003: Password Reset via Email

Users must be able to reset their password by requesting a reset link sent to
their registered email address.

- [ ] Reset link is delivered within 60 seconds
- [ ] Link expires after 24 hours
- [ ] New password must meet complexity requirements (min 12 chars, mixed case, number, symbol)
- [ ] Previous 5 passwords cannot be reused

**Requirement Type:** Functional
**NFR Category:** N/A
**Priority:** P1
**Story Points:** 3
**Source:** Project kickoff meeting - 2026-08-01
**Clarification Status:** Confirmed
**Confidence:** Firm