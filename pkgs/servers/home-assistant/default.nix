{ stdenv, nixosTests, lib, fetchurl, fetchFromGitHub, fetchpatch, python3, protobuf3_6

# Look up dependencies of specified components in component-packages.nix
, extraComponents ? [ ]

# Additional packages to add to propagatedBuildInputs
, extraPackages ? ps: []

# Override Python packages using
# self: super: { pkg = super.pkg.overridePythonAttrs (oldAttrs: { ... }); }
# Applied after defaultOverrides
, packageOverrides ? self: super: {
}

# Skip pip install of required packages on startup
, skipPip ? true }:

let
  defaultOverrides = [
    # Override the version of some packages pinned in Home Assistant's setup.py

    # Pinned due to API changes in astral>=2.0, required by the sun/moon plugins
    # https://github.com/home-assistant/core/issues/36636
    (mkOverride "astral" "1.10.1"
      "d2a67243c4503131c856cafb1b1276de52a86e5b8a1d507b7e08bee51cb67bf1")

    # Pinned due to an API change in pyowm>=3.0
    # Remove after https://github.com/home-assistant/core/pull/39839 gets merged
    (mkOverride "pyowm" "2.10.0"
      "1xvcv3sbcn9na8cwz21nnjlixysfk5lymnf65d1nqkbgacc1mm4g")

    # Pinned, because v1.5.0 broke the google_translate integration
    # https://github.com/home-assistant/core/pull/38428
    (mkOverride "yarl" "1.4.2"
      "0jzpgrdl6415zzl8js7095q8ks14555lhgxah76mimffkr39rkaq")

    # hass-frontend does not exist in python3.pkgs
    (self: super: {
      hass-frontend = self.callPackage ./frontend.nix { };
    })
  ];

  mkOverride = attrname: version: sha256:
    self: super: {
      ${attrname} = super.${attrname}.overridePythonAttrs (oldAttrs: {
        inherit version;
        src = oldAttrs.src.override {
          inherit version sha256;
        };
      });
    };

  py = python3.override {
    # Put packageOverrides at the start so they are applied after defaultOverrides
    packageOverrides = lib.foldr lib.composeExtensions (self: super: { }) ([ packageOverrides ] ++ defaultOverrides);
  };

  componentPackages = import ./component-packages.nix;

  availableComponents = builtins.attrNames componentPackages.components;

  getPackages = component: builtins.getAttr component componentPackages.components;

  componentBuildInputs = lib.concatMap (component: getPackages component py.pkgs) extraComponents;

  # Ensure that we are using a consistent package set
  extraBuildInputs = extraPackages py.pkgs;

  # Don't forget to run parse-requirements.py after updating
  hassVersion = "0.117.1";

in with py.pkgs; buildPythonApplication rec {
  pname = "homeassistant";
  version = assert (componentPackages.version == hassVersion); hassVersion;

  # check REQUIRED_PYTHON_VER in homeassistant/const.py
  disabled = pythonOlder "3.7.1";

  inherit availableComponents;

  # PyPI tarball is missing tests/ directory
  src = fetchFromGitHub {
    owner = "home-assistant";
    repo = "core";
    rev = version;
    sha256 = "1ifkxgsdm6bvrf573z75ry7vvrb3zi67x5j2nlsb44igfmk0nj1v";
  };

  postPatch = ''
    substituteInPlace setup.py \
      --replace "bcrypt==3.1.7" "bcrypt>=3.1.7" \
      --replace "cryptography==3.2.0" "cryptography" \
      --replace "ruamel.yaml==0.15.100" "ruamel.yaml>=0.15.100"
    substituteInPlace tests/test_config.py --replace '"/usr"' '"/build/media"'
  '';

  propagatedBuildInputs = [
    # From setup.py
    aiohttp astral async-timeout attrs bcrypt certifi ciso8601 httpx jinja2
    pyjwt cryptography pip python-slugify pytz pyyaml requests ruamel_yaml
    setuptools voluptuous voluptuous-serialize yarl
    # From default_config. frontend, http, image, mobile_app and recorder components as well as
    # the auth.mfa_modules.totp module
    aiohttp-cors defusedxml distro emoji hass-frontend pynacl pillow pyotp
    pyqrcode sqlalchemy
  ] ++ componentBuildInputs ++ extraBuildInputs;

  # upstream only tests on Linux, so do we.
  doCheck = stdenv.isLinux;

  checkInputs = [
    asynctest pytestCheckHook pytest-aiohttp pytest_xdist requests-mock hass-nabucasa netdisco pydispatcher
  ];

  # We cannot test all components, since they'd introduce lots of dependencies, some of which are unpackaged,
  # but we should test very common stuff, like what's in `default_config`.
  componentTests = [
    "api"
    "automation"
    "config"
    "configurator"
    "default_config"
    "demo"
    "discovery"
    "frontend"
    "group"
    "history"
    "homeassistant"
    "http"
    "input_boolean"
    "input_datetime"
    "input_text"
    "input_number"
    "input_select"
    "logbook"
    "logger"
    "media_source"
    "mobile_app"
    "person"
    "scene"
    "script"
    "shell_command"
    "ssdp"
    "sun"
    "system_health"
    "system_log"
    "tag"
    "websocket_api"
    "zeroconf"
    "zone"
  ];

  pytestFlagsArray = [
    "-n auto"
    # don't bulk test all components
    "--ignore tests/components"
    # prone to race conditions due to parallel file access
    "--ignore tests/test_config.py"
    # tries to import unpackaged dependencies
    "--ignore tests/test_loader.py"
    # pyotp since v2.4.0 complains about the short mock keys, hass pins v2.3.0
    "--ignore tests/auth/mfa_modules/test_notify.py"
    "tests"
  ] ++ map (component: "tests/components/" + component) componentTests;

  disabledTests = [
    # AssertionError: merge_log_err.call_count != 0
    "test_merge"
    # ModuleNotFoundError: No module named 'pyqwikswitch'
    "test_merge_id_schema"
    # AssertionError: assert 'unknown' == 'not_home'
    "test_device_tracker_not_home"
    # Racy https://github.com/home-assistant/core/issues/41425
    "test_cached_event_message"
  ];

  preCheck = ''
    # the tests require the existance of a media dir
    mkdir /build/media
  '';

  makeWrapperArgs = lib.optional skipPip "--add-flags --skip-pip";

  passthru = {
    inherit (py.pkgs) hass-frontend;
    tests = {
      inherit (nixosTests) home-assistant;
    };
  };

  meta = with lib; {
    homepage = "https://home-assistant.io/";
    description = "Open source home automation that puts local control and privacy first";
    license = licenses.asl20;
    maintainers = with maintainers; [ dotlambda globin mic92 hexa ];
  };
}
