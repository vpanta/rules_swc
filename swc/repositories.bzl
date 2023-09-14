"""Repository rules for fetching the swc toolchain.

For typical usage, see the snippets provided in the rules_swc release notes.

### Version matching

To keep the swc version in sync with non-Bazel tooling, use `swc_version_from`.

Currently this only works when a single, pinned version appears, see:
https://github.com/aspect-build/rules_ts/issues/308

For example, `package.json`:

```json
{
  "devDependencies": {
    "@swc/core": "1.3.37"
  }
}
```

Allows this in `WORKSPACE`:

```starlark
swc_register_toolchains(
    name = "swc",
    swc_version_from = "//:package.json",
)
```

### Other versions

To use an swc version which is not mirrored to rules_swc, use `integrity_hashes`.

For example in `WORKSPACE`:

```starlark
swc_register_toolchains(
    name = "swc",
    integrity_hashes = {
        "darwin-arm64": "sha384-IhP/76Zi5PEfsrGwPJj/CLHu2afxSBO2Fehp/qo4uHVXez08dcfyd9UzrcUI1z1q",
        "darwin-x64": "sha384-s2wH7hzaMbTbIkgPpP5rAYThH/+H+RBQ/5xKbpM4lfwPMS6cNBIpjKVnathrENm/",
        "linux-arm64-gnu": "sha384-iaBhMLrnHTSfXa86AVHM6zHqYbH3Fh1dWwDeH7sW9HKvX2gbQb6LOpWN6Wp4ddud",
        "linux-x64-gnu": "sha384-R/y9mcodpNt8l6DulUCG5JsNMrApP+vOAAh3bTRChh6LQKP0Z3Fwq86ztfObpAH8",
    },
    swc_version = "v1.3.37",
)
```

You can use the [`mirror_releases.sh` script](https://github.com/aspect-build/rules_swc/blob/main/scripts/mirror_releases.sh) to generate the expected shas. For example:
```
> mirror_releases.sh v1.3.50
    "v1.3.50": {
        "darwin-arm64": "sha384-kXrPSxzwUCsB2y0ivQrCrBDULa+N9BwwtKzqo4hIgYmgZgBGP8cXfEWlM18Pe2mT",
        "darwin-x64": "sha384-xRo3yRFsS8w5I7uWG7ZDpDiIhlJVUADpXzCWCNkYEsO4vJGD3izvTCUyWcF6HaRj",
        "linux-arm-gnueabihf": "sha384-WoVw65RR2yq7fZGRpGKGDwyloteD2XjxMkqVDip2BkKuGVZMDjqldivLYx56Nhzq",
        "linux-arm64-gnu": "sha384-f1pB/FU6PVYSW8KIFA799chHgXPeoaH2z8E82Mc2V21pQeJWITasy5h5wPHghZ9i",
        "linux-x64-gnu": "sha384-MdR0sNOSZG4AfCBQFfqSGJ5A9Zi5mMgL7wdIeQpzqjkPICK2uDl5/MgJbO4D3kAM",
        "win32-arm64-msvc": "sha384-PSmCSGrZBoFg8D+S7NqmlVr4HSedlWU2IsF0eci9jUQb+eBJeco3IO4V+IIhCiKw",
        "win32-ia32-msvc": "sha384-HXRGllEV7LnLN/tgB5FfspniKG3y43C1bKIatDQIWk56gekAzm1ntV1W0qAYjz3M",
        "win32-x64-msvc": "sha384-0oZDYXsh1Aeiqt9jA/HcWEM/yMXoC7fQvkPhDjUf0nVimZuPehj4BPWCyiIsrD1s",
    },
```

"""

load("@bazel_skylib//lib:versions.bzl", "versions")
load("//swc/private:toolchains_repo.bzl", "PLATFORMS", "toolchains_repo")
load("//swc/private:versions.bzl", "TOOL_VERSIONS")

# Expose as Public API
LATEST_SWC_VERSION = TOOL_VERSIONS.keys()[0]

# TODO(2.0): remove this alias
LATEST_VERSION = LATEST_SWC_VERSION

_DOC = "Fetch external dependencies needed to run the SWC cli"
_ATTRS = {
    "swc_version": attr.string(doc = "Explicit version. If provided, the package.json is not read."),
    "swc_version_from": attr.label(doc = "Location of package.json which has a version for @swc/core."),
    "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
    "integrity_hashes": attr.string_dict(doc = "A mapping from platform to integrity hash."),
}

# This package is versioned the same as the underlying rust binary we download
_NPM_PKG = "@swc/core"

_SWC_TOO_OLD = """

FATAL: swc version must be at least 1.3.25, as prior versions had bugs in the pure-rust CLI.

If you need swc version {}, then use rules_swc v0.20.2 or earlier.
Those releases of rules_swc call the NodeJS @swc/cli to access the Rust binding,
so they aren't affected by these bugs.

"""

# Read the swc version from package.json if requested
def _determine_version(rctx):
    if rctx.attr.swc_version:
        return rctx.attr.swc_version

    json_path = rctx.path(rctx.attr.swc_version_from)
    p = json.decode(rctx.read(json_path))
    if "devDependencies" in p.keys() and _NPM_PKG in p["devDependencies"]:
        v = p["devDependencies"][_NPM_PKG]
    elif "dependencies" in p.keys() and _NPM_PKG in p["dependencies"]:
        v = p["dependencies"][_NPM_PKG]
    else:
        fail("key '{}' not found in either dependencies or devDependencies of {}".format(_NPM_PKG, json_path))
    if any([not seg.isdigit() for seg in v.split(".")]):
        fail("{} version in package.json must be exactly specified, not a semver range: {}.\n".format(_NPM_PKG, v) +
             "You can supply an exact 'swc_version' attribute to 'swc_register_toolchains' to bypass this check.")

    # package.json versions don't have a "v" prefix, but github distribution/tag does.
    return "v" + v

def _swc_repo_impl(repository_ctx):
    version = _determine_version(repository_ctx)
    if not versions.is_at_least("1.3.25", version.lstrip("v")):
        fail(_SWC_TOO_OLD.format(version))
    filename = "swc-" + repository_ctx.attr.platform

    # The binaries of the SWC cli releases for windows are suffixed with ".exe"
    if repository_ctx.attr.platform.startswith("win32"):
        filename += ".exe"

    url = "https://github.com/swc-project/swc/releases/download/{0}/{1}".format(
        version,
        filename,
    )

    integrity = repository_ctx.attr.integrity_hashes.get(
        repository_ctx.attr.platform,
        None,
    )
    if not integrity:
        if version not in TOOL_VERSIONS.keys():
            fail("""\
swc version {} does not have hashes mirrored in aspect_rules_swc, please either
    - Set the integrity_hashes attribute to a dictionary of platform/hash
    - Choose one of the mirrored versions: {}
""".format(version, TOOL_VERSIONS.keys()))

        integrity = TOOL_VERSIONS[version][repository_ctx.attr.platform]

    repository_ctx.download(
        output = filename,
        url = url,
        integrity = integrity,
        executable = True,
    )
    build_content = """#Generated by swc/repositories.bzl
load("@aspect_rules_swc//swc:toolchain.bzl", "swc_toolchain")
swc_toolchain(
    name = "swc_toolchain",
    target_tool = "%s",
)
""" % filename

    # Base BUILD file for this repository
    repository_ctx.file("BUILD.bazel", build_content)

swc_repositories = repository_rule(
    _swc_repo_impl,
    doc = _DOC,
    attrs = _ATTRS,
)

# Wrapper macro around everything above, this is the primary API
def swc_register_toolchains(name, swc_version = None, swc_version_from = None, register = True, **kwargs):
    """Convenience macro for users which does typical setup.

    - create a repository for each built-in platform like "swc_linux_amd64"
    - create a repository exposing toolchains for each platform like "swc_platforms"
    - register a toolchain pointing at each platform
    Users can avoid this macro and do these steps themselves, if they want more control.

    Args:
        name: base name for all created repos; we recommend `swc`
        swc_version_from: label of a json file (typically `package.json`) which declares an exact `@swc/core` version
            in a dependencies or devDependencies property.
            Exactly one of `swc_version` or `swc_version_from` must be set.
        swc_version: version of the swc project, from https://github.com/swc-project/swc/releases
            Exactly one of `swc_version` or `swc_version_from` must be set.
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
        **kwargs: passed to each swc_repositories call
    """

    if (swc_version and swc_version_from) or (not swc_version_from and not swc_version):
        fail("Exactly one of 'swc_version' or 'swc_version_from' must be set.")

    for platform in PLATFORMS.keys():
        swc_repositories(
            name = name + "_" + platform,
            platform = platform,
            swc_version = swc_version,
            swc_version_from = swc_version_from,
            **kwargs
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )
