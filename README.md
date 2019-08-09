# Aragon Presale app

## Notice: This repository is frozen!
It has been ported to act as an Aragon Black Fundraising app module, and submitted as a PR that is currently being discussed: https://github.com/AragonBlack/fundraising/pull/52

Bootstraps an Aragon Black Fundraising app: https://github.com/AragonBlack/fundraising

#### Development

To compile and run the Presale app and its tests with a Fundraising app:

```
npm i
npm run link-ablack-apps
npm run ganache-cli:dev
npm run compile:dev
npm run test:dev
```

#### Aragon Black apps linkage

There is a rather rudimentary linkage to the Aragon Black apps in this project, since these are not yet published in NPM.

In package.json, the fundraising code is fetched as a dependency:
```
    "@ablack/fundraising": "AragonBlack/fundraising#bg-updates",
```

And the script `./scripts/link-ablack-apps.sh` simply creates a bunch of symlinks that simulate the published packages from the fundraising repository code.
