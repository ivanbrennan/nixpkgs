{ stdenv
, fetchFromGitHub
, cmake
, pkg-config
, gtkmm3
, lib
}:

stdenv.mkDerivation rec {
  pname = "picket";
  # The following PR added support for installing outside of /usr, but that
  # hasn't made it into an official release yet, so we point at a specific
  # commit, rather than a version tag.
  # https://github.com/rajter/picket/pull/5
  version = "1.3rev-73c491d";

  src = fetchFromGitHub {
    owner = "rajter";
    repo = pname;
    rev = "73c491d947d0cd4c8bc45b85f652ae63438e6025";
    sha256 = "sha256-zWZXYO+TwcZMT/Ncnik2afzlfpv+k3fm3u2Mirqsb/k=";
  };

  nativeBuildInputs = [ cmake pkg-config ];

  buildInputs = [ gtkmm3 ];

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

  meta = with lib; {
    description = "Native linux screen color picker with custom format output";
    homepage = "https://github.com/rajter/picket";
    license = licenses.mit;
    maintainers = [ maintainers.ivanbrennan ];
    platforms = platforms.linux;
  };
}
