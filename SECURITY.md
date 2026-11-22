# Security policy

EucLink holds two powerful macOS permissions, Input Monitoring and Accessibility. A bug
that lets another program borrow them, or makes the button run something its owner did not
choose, is a security problem. Please report it privately.

## Reporting a vulnerability

Use **Security > Report a vulnerability** on this repository. That opens a private advisory
that only the maintainer can see. Do not open a public issue.

Include:

- what an attacker can do, and what they need first (for example "a program running under
  the same user account");
- steps to reproduce, with your macOS version and EucLink version;
- a proof of concept if you have one.

## What happens next

- You get a reply within 7 days.
- Confirmed problems are fixed in a new release, and the advisory is published after the fix,
  crediting you unless you ask not to be named.
- EucLink is maintained by one person in their spare time, so a complex fix can take longer.
  You will hear how it is going.

## Supported versions

Only the latest release gets security fixes.

## Scope

In scope: the app, `build.sh`, `make-cert.sh` and `uninstall.sh`. The README's
[Security notes](README.md#security-notes) describe what EucLink defends against today.

Out of scope: attacks that already need administrator rights or physical access to an
unlocked Mac, and problems in the target apps EucLink presses keys for.
