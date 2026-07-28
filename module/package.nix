{ pkgs, softwareRendering ? false, browser ? null }:

let
  inherit (pkgs) lib stdenv fetchurl;
  pname = "microsoft-azurevpnclient";
  version = "3.0.0";

  # Resolve the configured browser into an executable command. Accepts either a
  # package (its main program is used) or a literal command string.
  browserCommand =
    if browser == null then null
    else if lib.isString browser then browser
    else lib.getExe browser;

  # When a browser is configured, shadow xdg-open with a shim that opens URLs
  # with that browser directly. On WSL, the real xdg-open detects the WSL
  # environment and hands URLs to the Windows host browser via rundll32.exe;
  # this shim keeps interactive auth inside WSL instead. The shim is placed
  # ahead of xdg-utils in the client's PATH so the client picks it up.
  browserShim = lib.optional (browserCommand != null)
    (pkgs.writeShellScriptBin "xdg-open" ''
      exec ${browserCommand} "$@"
    '');

  runtimeLibs = with pkgs; [
    atk
    cairo
    curl
    fontconfig
    freetype
    glib
    gtk3
    harfbuzz
    libcap
    libepoxy
    libsecret
    openssl
    pango
    sqlite
    stdenv.cc.cc.lib
    systemd
    zlib
  ];

in stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://packages.microsoft.com/ubuntu/22.04/prod/pool/main/m/${pname}/${pname}_${version}_amd64.deb";
    hash = "sha256-nl02BDPR03TZoQUbspplED6BynTr6qNRVdHw6fyUV3s=";
  };

  nativeBuildInputs = with pkgs; [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    mkdir -p $out/bin

    install -d $out/opt/microsoft/${pname}
    cp -r opt/microsoft/${pname}/* $out/opt/microsoft/${pname}/

    patchelf --set-rpath "${lib.makeLibraryPath runtimeLibs}:$out/opt/microsoft/${pname}/lib" \
      $out/opt/microsoft/${pname}/${pname}

    makeWrapper $out/opt/microsoft/${pname}/${pname} \
      $out/bin/azurevpnclient-unprivileged \
      --set GTK_USE_PORTAL 1 \
      ${lib.optionalString softwareRendering "--set GALLIUM_DRIVER llvmpipe --set LIBGL_ALWAYS_SOFTWARE 1"} \
      --prefix PATH : "${lib.makeBinPath (browserShim ++ (with pkgs; [ zenity xdg-utils ]))}" \
      --prefix LD_LIBRARY_PATH : "$out/opt/microsoft/${pname}/lib"

    install -Dm644 usr/share/icons/${pname}.png \
      $out/share/icons/hicolor/64x64/apps/${pname}.png

    install -Dm644 /dev/stdin $out/share/applications/${pname}.desktop <<EOF
[Desktop Entry]
Name=Azure VPN Client
Exec=azurevpnclient
Icon=microsoft-azurevpnclient
Type=Application
Categories=Network;
StartupNotify=true
StartupWMClass=${pname}
EOF
  '';

  meta = with lib; {
    description = "Microsoft Azure VPN Client for Linux";
    homepage = "https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-vpn-client-linux";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
