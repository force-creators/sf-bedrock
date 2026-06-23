# Contributing

Thanks for taking the time to improve sf-bedrock.

## Before You Start

- Open an issue for substantial changes before starting implementation work.
- Keep pull requests focused on one bug fix, feature, or documentation update.
- Preserve the existing project structure and Salesforce DX source format.

## Local Setup

Install dependencies from the repository root:

```sh
npm install
npm --prefix docs install
```

Build the documentation site:

```sh
npm run docs -- build
```

Run local JavaScript linting:

```sh
npm run lint
```

Check formatting:

```sh
npm run prettier:verify
```

Salesforce validation requires an authenticated org and the project aliases used
by the repository scripts. Run the relevant Apex validation before submitting
library changes.

## Pull Requests

- Include tests or validation notes for behavior changes.
- Update documentation when public APIs, setup steps, or expected behavior
  change.
- Do not commit local Salesforce state, generated build output, dependencies, or
  editor-specific files.

By contributing, you agree that your contribution is made available under the
Mozilla Public License, v. 2.0.
