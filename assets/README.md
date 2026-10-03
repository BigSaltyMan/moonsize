# Vendored assets

## `echarts.min.js`

Apache ECharts, the chart library the HTML report is drawn with.

| | |
|---|---|
| Package | `echarts@5.6.0` |
| File | `dist/echarts.min.js` |
| Size | 1,034,102 bytes |
| SHA-256 | `bf4a223524e40b77c304bec67e1222cf551f14880cf42c69dc046558e11c07b1` |
| Licence | Apache-2.0 (see the banner at the top of the file) |

It is vendored rather than loaded from a CDN so that `moonsize --html` produces a
report that opens with no network connection, which is the same promise the rest
of the tool makes: everything happens on the machine you run it on.

### Updating

```sh
# Fetch the tarball the registry publishes for the version you want, verify it
# against the integrity hash from https://registry.npmjs.org/echarts/<version>,
# then extract the one file this repository needs.
curl -sSLo echarts.tgz https://registry.npmjs.org/echarts/-/echarts-<version>.tgz
tar xzf echarts.tgz package/dist/echarts.min.js
cp package/dist/echarts.min.js assets/echarts.min.js
sha256sum assets/echarts.min.js   # update the hash above
```

Verifying against the registry tarball rather than against a CDN matters: this
file ends up embedded in generated reports and read by whoever opens them.
