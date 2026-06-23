<img src="docs/assets/icon.png" alt="Bedrock app icon" width="120" height="120">

# sf-bedrock

sf-bedrock is a Salesforce foundation library for Apex automation. It provides a
small set of base-org tools for predictable DML, query seams, test data,
trigger coordination, async work, event relay, scheduling, feature flags, and
other patterns that tend to become fragile when every project reinvents them.

Most users should start with the published documentation:

[sfbedrock.com](https://sfbedrock.com)

The repository is the source for the Bedrock Apex library and its docs site.

## What's Here

- `force-app/bedrock/lib/` contains the implemented Bedrock library source.
- `force-app/bedrock/console-app/` contains console UI and supporting Apex for
  operational tools.
- `docs/` contains the Astro docs site published at sfbedrock.com.
- `scripts/` contains small repository helpers for deployment, validation, and
  docs workflows.

## Local Docs

From the repository root, install dependencies once:

```sh
npm install
npm --prefix docs install
```

Open the docs locally:

```sh
npm run docs
```

That command builds the docs, starts Astro on `http://localhost:4321/`, and
opens the site in your browser when the local URL is ready.

Build the docs without starting a dev server:

```sh
npm run docs -- build
```

You can also run Astro directly from the docs project:

```sh
cd docs
npm run dev
npm run build
npm run preview
```

## Salesforce Development

The Salesforce DX project is configured in `sfdx-project.json`. The default
package directory is `force-app/bedrock/lib`, and the project uses Salesforce
API version `66.0`.

Repository helper commands target the `sf-bedrock` org alias:

```sh
npm run deploy
npm run deploy -- query
npm run deploy -- force-app/bedrock/lib/query --dry-run
```

Run Apex tests:

```sh
npm run validate
npm run validate -- query
npm run validate -- force-app/bedrock/lib/query --wait 20
```

For a full local formatting pass:

```sh
npm run prettier
```

To check formatting without writing files:

```sh
npm run prettier:verify
```

## Documentation Work

Before adding or changing library reference pages, read
[`docs/AUTHORING.md`](docs/AUTHORING.md). API claims in the docs should be
verified against the source in `force-app/bedrock/lib`, not roadmap notes or
prototype code.

The docs build should pass before documentation changes are considered ready:

```sh
npm run docs -- build
```

## License

sf-bedrock is licensed under the Mozilla Public License, v. 2.0. See
[`LICENSE`](LICENSE).

Copyright 2026 Matthew Swing-McKenzie & Force Creators. See [`NOTICE.md`](NOTICE.md) and
[`TRADEMARKS.md`](TRADEMARKS.md) for attribution and project identity guidance.
