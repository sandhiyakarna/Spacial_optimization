# FlowSpace Design Rules

Version: 1.0

---

# Purpose

This document defines the official UI/UX rules for FlowSpace.

All frontend implementation must follow these guidelines.

---

# Design Philosophy

FlowSpace is a premium AI-powered interior design platform.

The interface should feel:

- Modern
- Minimal
- Professional
- Spacious
- Premium
- Easy to navigate

Avoid clutter.

Always prioritize usability.

---

# Layout

Use an 8px spacing system.

Spacing

4px

8px

16px

24px

32px

48px

64px

---

# Border Radius

Buttons

14px

Cards

18px

Dialogs

20px

Input Fields

12px

Bottom Sheets

24px

---

# Shadows

Use soft shadows.

Avoid heavy dark shadows.

Cards

Small elevation

Dialogs

Medium elevation

Floating Buttons

Medium elevation

---

# Typography

Use Material 3 typography.

Hierarchy

Display

Headline

Title

Body

Label

Avoid more than 3 font weights on one screen.

---

# Buttons

Primary

Filled

Secondary

Outlined

Danger

Red Filled

Floating Action Button

Rounded

Use icons whenever appropriate.

---

# Icons

Use Material Symbols Rounded.

Maintain consistent icon sizes.

Small

20px

Medium

24px

Large

28px

---

# Cards

Cards should contain

Title

Optional subtitle

Content

Actions

Cards should not exceed necessary height.

---

# Navigation

Global Navigation

Home

Projects

Insights

Notifications

Profile

Project Navigation

Rooms

Designer

Analysis

History

Do not mix both navigation systems.

---

# Forms

Keep forms short.

Group related fields.

Provide validation.

Provide helpful error messages.

---

# Animations

Animation Duration

200–300ms

Transitions

Fade

Slide

Scale

Hero

Avoid excessive animations.

---

# Loading States

Every API request should have

Loading

Empty

Success

Error

State

---

# Responsive Design

Support

Phone

Tablet

Desktop

No overflow.

No clipped widgets.

---

# Accessibility

Touch targets

Minimum 48x48dp

High contrast

Readable text

Keyboard support

Screen reader friendly

---

# Consistency Rules

Reuse existing widgets whenever possible.

Do not create duplicate UI components.

Follow the official color palette.

Follow the official navigation workflow.

Follow the official UI mockups.

---

# Development Rules

Frontend changes only.

Reuse backend.

Reuse APIs.

Reuse providers.

Reuse models.

Reuse services.

Do not modify backend architecture unless required.

Always verify the application builds successfully after each completed screen.

One screen should be completed before moving to the next.