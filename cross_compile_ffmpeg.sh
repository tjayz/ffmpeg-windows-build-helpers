#!/usr/bin/env bash
# ffmpeg windows cross compile helper/download script, see github repo README
# Copyright (C) 2012 Roger Pack, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

yes_no_sel () {
  unset user_input
  local question="$1"
  shift
  local default_answer="$1"
  while [[ "$user_input" != [YyNn] ]]; do
    echo -n "$question"
    read user_input
    if [[ -z "$user_input" ]]; then
      echo "using default $default_answer"
      user_input=$default_answer
    fi
    if [[ "$user_input" != [YyNn] ]]; then
      clear; echo 'Your selection was not vaild, please try again.'; echo
    fi
  done
  # downcase it
  user_input=$(echo $user_input | tr '[A-Z]' '[a-z]')
}

set_box_memory_size_bytes() {
  if [[ $OSTYPE == darwin* ]]; then
    box_memory_size_bytes=20000000000 # 20G fake it out for now :|
  else
    local ram_kilobytes=`grep MemTotal /proc/meminfo | awk '{print $2}'`
    local swap_kilobytes=`grep SwapTotal /proc/meminfo | awk '{print $2}'`
    box_memory_size_bytes=$[ram_kilobytes * 1024 + swap_kilobytes * 1024]
  fi
}

function sortable_version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

at_least_required_version() { # params: required actual
  local sortable_required=$(sortable_version $1)
  sortable_required=$(echo $sortable_required | sed 's/^0*//') # remove preceding zeroes, which bash later interprets as octal or screwy
  local sortable_actual=$(sortable_version $2)
  sortable_actual=$(echo $sortable_actual | sed 's/^0*//')
  [[ "$sortable_actual" -ge "$sortable_required" ]]
}

apt_not_installed() {
  for x in "$@"; do
    if ! dpkg -l "$x" | grep -q '^.i'; then
      need_install="$need_install $x"
    fi
  done
  echo "$need_install"
}

check_missing_packages () {
  # We will need this later if we don't want to just constantly be grepping the /etc/os-release file
  if [ -z "${VENDOR}" ] && grep -E '(centos|rhel)' /etc/os-release &> /dev/null; then
    # In RHEL this should always be set anyway. But not so sure about CentOS
    VENDOR="redhat"
  fi
  # zeranoe's build scripts use wget, though we don't here...
  local check_packages=('ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' 'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'makeinfo' 'g++' 'ed' 'pax' 'unzip' 'patch' 'wget' 'xz' 'nasm' 'gperf' 'autogen' 'bzip2' 'realpath' 'clang' 'python' 'bc' 'autopoint' 'ninja')
  # autoconf-archive is just for leptonica FWIW
  # I'm not actually sure if VENDOR being set to centos is a thing or not. On all the centos boxes I can test on it's not been set at all.
  # that being said, if it where set I would imagine it would be set to centos... And this contition will satisfy the "Is not initially set"
  # case because the above code will assign "redhat" all the time.
  if [ -z "${VENDOR}" ] || [ "${VENDOR}" != "redhat" ] && [ "${VENDOR}" != "centos" ]; then
    check_packages+=('cmake')
  fi
  # libtool check is wonky...
  if [[ $OSTYPE == darwin* ]]; then
    check_packages+=('glibtoolize') # homebrew special :|
  else
    check_packages+=('libtoolize') # the rest of the world
  fi
  # Use hash to check if the packages exist or not. Type is a bash builtin which I'm told behaves differently between different versions of bash.
  for package in "${check_packages[@]}"; do
    hash "$package" &> /dev/null || missing_packages=("$package" "${missing_packages[@]}")
  done
  if [ "${VENDOR}" = "redhat" ] || [ "${VENDOR}" = "centos" ]; then
    if [ -n "$(hash cmake 2>&1)" ] && [ -n "$(hash cmake3 2>&1)" ]; then missing_packages=('cmake' "${missing_packages[@]}"); fi
  fi
  if [[ -n "${missing_packages[@]}" ]]; then
    clear
    echo "Could not find the following execs (svn is actually package subversion, makeinfo is actually package texinfo if you're missing them): ${missing_packages[*]}"
    echo 'Install the missing packages before running this script.'
    determine_distro

    apt_pkgs='subversion ragel curl texinfo g++ ed bison flex cvs yasm automake libtool autoconf gcc cmake git make pkg-config zlib1g-dev unzip pax nasm gperf autogen bzip2 autoconf-archive p7zip-full clang wget bc autopoint python3-full ninja-build'

    [[ $DISTRO == "debian" ]] && apt_pkgs="$apt_pkgs libtool-bin ed" # extra for debian
    case "$DISTRO" in
      Ubuntu)
        echo "for ubuntu:"
        echo "$ sudo apt-get update"
        ubuntu_ver="$(lsb_release -rs)"
        if at_least_required_version "20.04" "$ubuntu_ver"; then
          apt_pkgs="$apt_pkgs python-is-python3" # needed
        fi
        echo "$ sudo apt-get install $apt_pkgs -y"
        if uname -a | grep  -q -- "-microsoft" ; then
         echo NB if you use WSL Ubuntu 20.04 you need to do an extra step: https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452
	fi
        ;;
      debian)
        echo "for debian:"
        echo "$ sudo apt-get update"
        # Debian version is always encoded in the /etc/debian_version
        # This file is deployed via the base-files package which is the essential one - deployed in all installations.
        # See their content for individual debian releases - https://sources.debian.org/src/base-files/
        # Stable releases contain a version number.
        # Testing/Unstable releases contain a textual codename description (e.g. bullseye/sid)
        #
        deb_ver="$(cat /etc/debian_version)"
        # Upcoming codenames taken from https://en.wikipedia.org/wiki/Debian_version_history
        #
        if [[ $deb_ver =~ bullseye ]]; then
            deb_ver="11"
        elif [[ $deb_ver =~ bookworm ]]; then
            deb_ver="12"
        elif [[ $deb_ver =~ trixie ]]; then
            deb_ver="13"
        fi
        if at_least_required_version "11" "$deb_ver"; then
          apt_pkgs="$apt_pkgs python-is-python3" # needed
        fi
        apt_missing="$(apt_not_installed "$apt_pkgs")"
        echo "$ sudo apt-get install $apt_missing -y"
        ;;
      *)
        echo "for OS X (homebrew): brew install ragel wget cvs yasm autogen automake autoconf cmake libtool xz pkg-config nasm bzip2 autoconf-archive p7zip coreutils llvm" # if edit this edit docker/Dockerfile also :|
        echo "   and set llvm to your PATH if on catalina"
        echo "for RHEL/CentOS: First ensure you have epel repo available, then run $ sudo yum install ragel subversion texinfo libtool autogen gperf nasm patch unzip pax ed gcc-c++ bison flex yasm automake autoconf gcc zlib-devel cvs bzip2 cmake3 -y"
        echo "for fedora: if your distribution comes with a modern version of cmake then use the same as RHEL/CentOS but replace cmake3 with cmake."
        echo "for linux native compiler option: same as <your OS> above, also add libva-dev"
        ;;
    esac
    exit 1
  fi

  export REQUIRED_CMAKE_VERSION="3.0.0"
  for cmake_binary in 'cmake' 'cmake3'; do
    # We need to check both binaries the same way because the check for installed packages will work if *only* cmake3 is installed or
    # if *only* cmake is installed.
    # On top of that we ideally would handle the case where someone may have patched their version of cmake themselves, locally, but if
    # the version of cmake required move up to, say, 3.1.0 and the cmake3 package still only pulls in 3.0.0 flat, then the user having manually
    # installed cmake at a higher version wouldn't be detected.
    if hash "${cmake_binary}"  &> /dev/null; then
      cmake_version="$( "${cmake_binary}" --version | sed -e "s#${cmake_binary}##g" | head -n 1 | tr -cd '[0-9.\n]' )"
      if at_least_required_version "${REQUIRED_CMAKE_VERSION}" "${cmake_version}"; then
        export cmake_command="${cmake_binary}"
        break
      else
        echo "your ${cmake_binary} version is too old ${cmake_version} wanted ${REQUIRED_CMAKE_VERSION}"
      fi
    fi
  done

  # If cmake_command never got assigned then there where no versions found which where sufficient.
  if [ -z "${cmake_command}" ]; then
    echo "there where no appropriate versions of cmake found on your machine."
    exit 1
  else
    # If cmake_command is set then either one of the cmake's is adequate.
    if [[ $cmake_command != "cmake" ]]; then # don't echo if it's the normal default
      echo "cmake binary for this build will be ${cmake_command}"
    fi
  fi

  if [[ ! -f /usr/include/zlib.h ]]; then
    echo "warning: you may need to install zlib development headers first if you want to build mp4-box [on ubuntu: $ apt-get install zlib1g-dev] [on redhat/fedora distros: $ yum install zlib-devel]" # XXX do like configure does and attempt to compile and include zlib.h instead?
    sleep 1
  fi

  # TODO nasm version :|

  # doing the cut thing with an assigned variable dies on the version of yasm I have installed (which I'm pretty sure is the RHEL default)
  # because of all the trailing lines of stuff
  export REQUIRED_YASM_VERSION="1.2.0" # export ???
  local yasm_binary=yasm
  local yasm_version="$( "${yasm_binary}" --version |sed -e "s#${yasm_binary}##g" | head -n 1 | tr -dc '[0-9.\n]' )"
  if ! at_least_required_version "${REQUIRED_YASM_VERSION}" "${yasm_version}"; then
    echo "your yasm version is too old $yasm_version wanted ${REQUIRED_YASM_VERSION}"
    exit 1
  fi

  #check if WSL
  # check WSL for interop setting make sure its disabled
  # check WSL for kernel version look for version 4.19.128 current as of 11/01/2020
  if uname -a | grep  -iq -- "-microsoft" ; then
    if cat /proc/sys/fs/binfmt_misc/WSLInterop | grep -q enabled ; then
      echo "windows WSL detected: you must first disable 'binfmt' by running this
      sudo bash -c 'echo 0 > /proc/sys/fs/binfmt_misc/WSLInterop'
      then try again"
      #exit 1
    fi
    export MINIMUM_KERNEL_VERSION="4.19.128"
    KERNVER=$(uname -a | awk -F'[ ]' '{ print $3 }' | awk -F- '{ print $1 }')

    function version { # for version comparison @ stackoverflow.com/a/37939589
      echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
    }

    if [ $(version $KERNVER) -lt $(version $MINIMUM_KERNEL_VERSION) ]; then
      echo "Windows Subsystem for Linux (WSL) detected - kernel not at minumum version required: $MINIMUM_KERNEL_VERSION
      Please update via windows update then try again"
      #exit 1
    fi
    echo "for WSL ubuntu 20.04 you need to do an extra step https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452"
  fi

}

determine_distro() {

# Determine OS platform from https://askubuntu.com/a/459425/20972
UNAME=$(uname | tr "[:upper:]" "[:lower:]")
# If Linux, try to determine specific distribution
if [ "$UNAME" == "linux" ]; then
    # If available, use LSB to identify distribution
    if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
        export DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
    # Otherwise, use release info file
    else
        export DISTRO=$(grep '^ID' /etc/os-release | sed 's#.*=\(\)#\1#')
    fi
fi
# For everything else (or if above failed), just use generic identifier
[ "$DISTRO" == "" ] && export DISTRO=$UNAME
unset UNAME
}


intro() {
  cat <<EOL
     ##################### Welcome ######################
  Welcome to the ffmpeg cross-compile builder-helper script.
  Downloads and builds will be installed to directories within $cur_dir
  If this is not ok, then exit now, and cd to the directory where you'd
  like them installed, then run this script again from there.
  NB that once you build your compilers, you can no longer rename/move
  the sandbox directory, since it will have some hard coded paths in there.
  You can, of course, rebuild ffmpeg from within it, etc.
EOL
  echo `date` # for timestamping super long builds LOL
  if [[ $sandbox_ok != 'y' && ! -d sandbox ]]; then
    echo
    echo "Building in $PWD/sandbox, will use ~ 20GB space!"
    echo
  fi
  mkdir -p "$cur_dir"
  cd "$cur_dir"
  if [[ $disable_nonfree = "y" ]]; then
    non_free="n"
  else
    if  [[ $disable_nonfree = "n" ]]; then
      non_free="y"
    else
      yes_no_sel "Would you like to include non-free (non GPL compatible) libraries, like [libfdk_aac,decklink -- note that the internal AAC encoder is ruled almost as high a quality as fdk-aac these days]
The resultant binary may not be distributable, but can be useful for in-house use. Include these non-free license libraries [y/N]?" "n"
      non_free="$user_input" # save it away
    fi
  fi
  echo "sit back, this may take awhile..."
}

pick_compiler_flavors() {
  while [[ "$compiler_flavors" != [1-5] ]]; do
    if [[ -n "${unknown_opts[@]}" ]]; then
      echo -n 'Unknown option(s)'
      for unknown_opt in "${unknown_opts[@]}"; do
        echo -n " '$unknown_opt'"
      done
      echo ', ignored.'; echo
    fi
    cat <<'EOF'
What version of MinGW-w64 would you like to build or update?
  1. Both Win32 and Win64
  2. Win32 (32-bit only)
  3. Win64 (64-bit only)
  4. Local native
  5. Exit
EOF
    echo -n 'Input your choice [1-5]: '
    read compiler_flavors
  done
  case "$compiler_flavors" in
  1 ) compiler_flavors=multi ;;
  2 ) compiler_flavors=win32 ;;
  3 ) compiler_flavors=win64 ;;
  4 ) compiler_flavors=native ;;
  5 ) echo "exiting"; exit 0 ;;
  * ) clear;  echo 'Your choice was not valid, please try again.'; echo ;;
  esac
}

# made into a method so I don't have to download this script every time if only doing just 32 or just 64 bit builds...
download_gcc_build_script() {
    local zeranoe_script_name=$1
    rm -f $zeranoe_script_name || exit 1
    curl -4 file://$patch_dir/$zeranoe_script_name -O --fail || exit 1
    chmod u+x $zeranoe_script_name
}

install_cross_compiler() {
  local win32_gcc="sandbox/i686/bin/i686-w64-mingw32-gcc"
  local win64_gcc="sandbox/x86_64/bin/x86_64-w64-mingw32-gcc"
  if [[ -f $win32_gcc && -f $win64_gcc ]]; then
   echo "MinGW-w64 compilers both already installed, not re-installing..."
   if [[ -z $compiler_flavors ]]; then
     echo "selecting multi build (both win32 and win64)...since both cross compilers are present assuming you want both..."
     compiler_flavors=multi
   fi
   return # early exit they've selected at least some kind by this point...
  fi

  if [[ -z $compiler_flavors ]]; then
    pick_compiler_flavors
  fi
  if [[ $compiler_flavors == "native" ]]; then
    echo "native build, not building any cross compilers..."
    return
  fi

    unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
    # pthreads version to avoid having to use cvs for it
    echo "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count..."
    echo ""

    # --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
    local zeranoe_script_name=mingw-w64-build
    if [[ ! -f $HOME/sandbox/src/config.guess ]]; then
      local config_options=""
    else
	  local config_options="--cached-sources"
    fi
    local zeranoe_script_options="--gcc-branch=releases/gcc-15 $config_options"
    if [[ ($compiler_flavors == "win32" || $compiler_flavors == "multi") && ! -f ../$win32_gcc ]]; then
      echo "Building win32 cross compiler..."
      download_gcc_build_script $zeranoe_script_name
      if [[ `uname` =~ "5.1" ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
        sed -i "s/ --enable-secure-api//" $zeranoe_script_name
      fi
      CFLAGS='-O2' CXXFLAGS='-O2' nice ./$zeranoe_script_name $zeranoe_script_options i686 || exit 1 # i586 option needs work to implement
      if [[ ! -f ../$win32_gcc ]]; then
        echo "Failure building 32 bit gcc? Recommend nuke sandbox (rm -rf sandbox) and start over..."
        exit 1
      fi
      if [[ ! -f  $HOME/sandbox/mingw-w64-i686/i686-w64-mingw32/lib/libgomp.a ]]; then
	      echo "failure building libgomp? 32 bit"
	      exit 1
      fi
    fi
    if [[ ($compiler_flavors == "win64" || $compiler_flavors == "multi") && ! -f ../$win64_gcc ]]; then
      echo "Building win64 x86_64 cross compiler..."
      download_gcc_build_script $zeranoe_script_name
      CFLAGS='-O2' CXXFLAGS='-O2' nice ./$zeranoe_script_name $zeranoe_script_options x86_64 || exit 1
      if [[ ! -f ../$win64_gcc ]]; then
        echo "Failure building 64 bit gcc? Recommend nuke sandbox (rm -rf sandbox) and start over..."
        exit 1
      fi
      if [[ ! -f  $HOME/sandbox/x86_64/x86_64-w64-mingw32/lib/libgomp.a ]]; then
	      echo "failure building libgomp? 64 bit"
	      exit 1
      fi
    fi

    # rm -f build.log # leave resultant build log...sometimes useful...
    reset_cflags
    reset_cxxflags
  cd ..
  echo "Done building (or already built) MinGW-w64 cross-compiler(s) successfully..."
  echo `date` # so they can see how long it took :)
}

# helper methods for downloading and building projects that can take generic input

do_svn_checkout() {
  repo_url="$1"
  to_dir="$2"
  desired_revision="$3"
  if [ ! -d $to_dir ]; then
    echo "svn checking out to $to_dir"
    if [[ -z "$desired_revision" ]]; then
      svn checkout $repo_url $to_dir.tmp  --non-interactive --trust-server-cert || exit 1
    else
      svn checkout -r $desired_revision $repo_url $to_dir.tmp || exit 1
    fi
    mv $to_dir.tmp $to_dir
  else
    cd $to_dir
    echo "not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
    # XXX accomodate for desired revision here if I ever uncomment the next line...
    # svn up
    cd ..
  fi
}

# params: git url, to_dir
retry_git_or_die() {  # originally from https://stackoverflow.com/a/76012343/32453
  local RETRIES_NO=50
  local RETRY_DELAY=15
  local repo_url=$1
  local to_dir=$2

  for i in $(seq 1 $RETRIES_NO); do
   echo "Downloading (via git clone) $to_dir from $repo_url"
   rm -rf $to_dir.tmp # just in case it was interrupted previously...not sure if necessary...
   git clone $repo_url $to_dir.tmp --recurse-submodules && break
   # get here -> failure
   [[ $i -eq $RETRIES_NO ]] && echo "Failed to execute git cmd $repo_url $to_dir after $RETRIES_NO retries" && exit 1
   echo "sleeping before retry git"
   sleep ${RETRY_DELAY}
  done
  # prevent partial checkout confusion by renaming it only after success
  mv $to_dir.tmp $to_dir
  echo "done git cloning to $to_dir"
}

do_git_checkout() {
  local repo_url="$1"
  local to_dir="$2"
  if [[ -z $to_dir ]]; then
    to_dir=$(basename $repo_url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  fi
  local desired_branch="$3"
  if [ ! -d $to_dir ]; then
    retry_git_or_die $repo_url $to_dir
    cd $to_dir
  else
    cd $to_dir
    if [[ $git_get_latest = "y" ]]; then
      git fetch # want this for later...
    else
      echo "not doing git get latest pull for latest code $to_dir" # too slow'ish...
    fi
  fi

  # reset will be useless if they didn't git_get_latest but pretty fast so who cares...plus what if they changed branches? :)
  old_git_version=`git rev-parse HEAD`
  if [[ -z $desired_branch ]]; then
	# Check for either "origin/main" or "origin/master".
	if [ $(git show-ref | grep -e origin\/main$ -c) = 1 ]; then
		desired_branch="origin/main"
	elif [ $(git show-ref | grep -e origin\/master$ -c) = 1 ]; then
		desired_branch="origin/master"
	else
		echo "No valid git branch!"
		exit 1
	fi
  fi
  echo "doing git checkout $desired_branch"
  git -c 'advice.detachedHead=false' checkout "$desired_branch" || (git_hard_reset && git -c 'advice.detachedHead=false' checkout "$desired_branch") || (git reset --hard "$desired_branch") || exit 1 # can't just use merge -f because might "think" patch files already applied when their changes have been lost, etc...
  # vmaf on 16.04 needed that weird reset --hard? huh?
  if git show-ref --verify --quiet "refs/remotes/origin/$desired_branch"; then # $desired_branch is actually a branch, not a tag or commit
    git merge "origin/$desired_branch" || exit 1 # get incoming changes to a branch
  fi
  new_git_version=`git rev-parse HEAD`
  if [[ "$old_git_version" != "$new_git_version" ]]; then
    echo "got upstream changes, forcing re-configure. Doing git clean"
    git_hard_reset
  else
    echo "fetched no code changes, not forcing reconfigure for that..."
  fi
  cd ..
}

git_hard_reset() {
  git reset --hard # throw away results of patch files
  git clean -fx # throw away local changes; 'already_*' and bak-files for instance.
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  local beginning="$1"
  local extra_stuff="$2"
  local touch_name="${beginning}_$(echo -- $extra_stuff $CFLAGS $LDFLAGS | /usr/bin/env md5sum)" # md5sum to make it smaller, cflags to force rebuild if changes
  touch_name=$(echo "$touch_name" | sed "s/ //g") # md5sum introduces spaces, remove them
  echo "$touch_name" # bash cruddy return system LOL
}

do_configure() {
  local configure_options="$1"
  local configure_name="$2"
  if [[ "$configure_name" = "" ]]; then
    configure_name="./configure"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(get_small_touchfile_name already_configured "$configure_options $configure_name")
  if [ ! -f "$touch_name" ]; then
    # make uninstall # does weird things when run under ffmpeg src so disabled for now...

    echo "configuring $english_name ($PWD) as $ PKG_CONFIG_PATH=$PKG_CONFIG_PATH PATH=$bin_path:\$PATH $configure_name $configure_options" # say it now in case bootstrap fails etc.
    echo "all touch files" already_configured* touchname= "$touch_name"
    echo "config options "$configure_options $configure_name""
    if [ -f bootstrap ]; then
      ./bootstrap # some need this to create ./configure :|
    fi
    if [[ ! -f $configure_name && -f bootstrap.sh ]]; then # fftw wants to only run this if no configure :|
      ./bootstrap.sh
    fi
    if [[ ! -f $configure_name ]]; then
      echo "running autoreconf to generate configure file for us..."
      autoreconf -fiv # a handful of them require this to create ./configure :|
    fi
    rm -f already_* # reset
    chmod u+x "$configure_name" # In non-windows environments, with devcontainers, the configuration file doesn't have execution permissions
    nice -n 5 "$configure_name" $configure_options || { echo "failed configure $english_name"; exit 1;} # less nicey than make (since single thread, and what if you're running another ffmpeg nice build elsewhere?)
    touch -- "$touch_name"
    echo "doing preventative make clean"
    nice make clean -j $cpu_count # sometimes useful when files change, etc.
  #else
  #  echo "already configured $(basename $cur_dir2)"
  fi
}

do_make() {
  local extra_make_options="$1"
  extra_make_options="$extra_make_options -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "$extra_make_options" )

  if [ ! -f $touch_name ]; then
    echo
    echo "Making $cur_dir2 as $ PATH=$bin_path:\$PATH make $extra_make_options"
    echo
    if [ ! -f configure ]; then
      nice make clean -j $cpu_count # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
    fi
    nice make $extra_make_options || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "Already made $(dirname "$cur_dir2") $(basename "$cur_dir2") ..."
  fi
}

do_make_and_make_install() {
  local extra_make_options="$1"
  do_make "$extra_make_options"
  do_make_install "$extra_make_options"
}

do_make_install() {
  local extra_make_install_options="$1"
  local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
  if [[ -z $override_make_install_options ]]; then
    local make_install_options="install $extra_make_install_options"
  else
    local make_install_options="$override_make_install_options $extra_make_install_options"
  fi
  local touch_name=$(get_small_touchfile_name already_ran_make_install "$make_install_options")
  if [ ! -f $touch_name ]; then
    echo "make installing $(pwd) as $ PATH=$bin_path:\$PATH make $make_install_options"
    nice make $make_install_options || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake() {
  extra_args="$1"
  local build_from_dir="$2"
  if [[ -z $build_from_dir ]]; then
    build_from_dir="."
  fi
  local touch_name=$(get_small_touchfile_name already_ran_cmake "$extra_args")

  if [ ! -f $touch_name ]; then
    rm -f already_* # reset so that make will run again if option just changed
    local cur_dir2=$(pwd)
    if [ $bits_target = 32 ]; then
	  local config_options="-DCMAKE_SYSTEM_PROCESSOR=x86" 
	else
      local config_options="-DCMAKE_SYSTEM_PROCESSOR=AMD64" 
    fi	
    echo doing cmake in $cur_dir2 with PATH=$bin_path:\$PATH with extra_args=$extra_args like this:
    if [[ $compiler_flavors != "native" ]]; then
      local command="${build_from_dir} -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=0 -DCMAKE_SYSTEM_NAME=Windows\
	  -DCMAKE_FIND_ROOT_PATH=$x86_64_prefix -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY\
	  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++\
	  -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_Fortran_COMPILER=${cross_prefix}gfortran -DCMAKE_CUDA_COMPILER=nvcc -DCMAKE_INSTALL_PREFIX=$x86_64_prefix $config_options $extra_args"
	else
      local command="${build_from_dir} -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$x86_64_prefix $config_options $extra_args"
    fi
    echo "doing ${cmake_command}  -G\"Unix Makefiles\" $command"
    nice -n 5  ${cmake_command} -G"Unix Makefiles" $command || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake_from_build_dir() { # some sources don't allow it, weird XXX combine with the above :)
  source_dir="$1"
  extra_args="$2"
  do_cmake "$extra_args" "$source_dir"
}

do_cmake_and_install() {
  do_cmake "$1"
  do_make_and_make_install
}

activate_meson() {
  if [[ ! -e tutorial_env ]]; then # requires python3-full
    python3 -m venv tutorial_env 
    source tutorial_env/bin/activate
    python3 -m pip install meson
  else source tutorial_env/bin/activate
  fi
}

do_meson() {
    local configure_options="$1 --unity=off"
    local configure_name="$2"
    local configure_env="$3"
    local configure_noclean=""
    if [[ "$configure_name" = "" ]]; then
        configure_name="meson"
    fi
    local cur_dir2=$(pwd)
    local english_name=$(basename $cur_dir2)
    local touch_name=$(get_small_touchfile_name already_built_meson "$configure_options $configure_name $LDFLAGS $CFLAGS")
    if [ ! -f "$touch_name" ]; then
        if [ "$configure_noclean" != "noclean" ]; then
            make clean # just in case
        fi
        rm -f already_* # reset
        echo "Using meson: $english_name ($PWD) as $ PATH=$PATH ${configure_env} $configure_name $configure_options"
        #env
        "$configure_name" $configure_options || exit 1
        touch -- "$touch_name"
        make clean # just in case
    else
        echo "Already used meson $(basename $cur_dir2)"
    fi
}

generic_meson() {
    local extra_configure_options="$1"
    mkdir -pv build
    do_meson "--prefix=${x86_64_prefix} --libdir=${x86_64_prefix}/lib --buildtype=release --default-library=static $extra_configure_options" # --cross-file=${top_dir}/meson-cross.mingw.txt
}

generic_meson_ninja_install() {
    generic_meson "$1"
    do_ninja_and_ninja_install
}

do_ninja_and_ninja_install() {
    local extra_ninja_options="$1"
    do_ninja "$extra_ninja_options"
    local touch_name=$(get_small_touchfile_name already_ran_make_install "$extra_ninja_options")
    if [ ! -f $touch_name ]; then
        echo "ninja installing $(pwd) as $PATH=$PATH ninja -C build install $extra_make_options"
        ninja -C build install || exit 1
        touch $touch_name || exit 1
    fi
}

do_ninja() {
  local extra_make_options=" -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "${extra_make_options}")

  if [ ! -f $touch_name ]; then
    echo
    echo "ninja-ing $cur_dir2 as $ PATH=$PATH ninja -C build "${extra_make_options}"
    echo
    ninja -C build "${extra_make_options} || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "already did ninja $(basename "$cur_dir2")"
  fi
}

apply_patch() {
  local url=$1 # if you want it to use a local file instead of a url one [i.e. local file with local modifications] specify it like file://localhost/full/path/to/filename.patch
  local patch_type=$2
  if [[ -z $patch_type ]]; then
    patch_type="-p0" # some are -p1 unfortunately, git's default
  fi
  local patch_name=$(basename $url)
  local patch_done_name="$patch_name.done"
  if [[ ! -e $patch_done_name ]]; then
    if [[ -f $patch_name ]]; then
      rm $patch_name || exit 1 # remove old version in case it has been since updated on the server...
    fi
    curl -4 --retry 5 $url -O --fail || echo_and_exit "unable to download patch file $url"
    echo "applying patch $patch_name"
    patch $patch_type < "$patch_name" || exit 1
    touch $patch_done_name || exit 1
    # too crazy, you can't do do_configure then apply a patch?
    # rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
  #else
  #  echo "patch $patch_name already applied" # too chatty
  fi
}

echo_and_exit() {
  echo "failure, exiting: $1"
  exit 1
}

# takes a url, output_dir as params, output_dir optional
download_and_unpack_file() {
  url="$1"
  output_name=$(basename $url)
  output_dir="$2"
  if [[ -z $output_dir ]]; then
    output_dir=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx
  fi
  if [ ! -f "$output_dir/unpacked.successfully" ]; then
    echo "downloading $url" # redownload in case failed...
    if [[ -f $output_name ]]; then
      rm $output_name || exit 1
    fi

    #  From man curl
    #  -4, --ipv4
    #  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
    #  this option tells curl to resolve names to IPv4 addresses only.
    #  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
    #  -L means "allow redirection" or some odd :|

    curl -4 "$url" --retry 50 -O -L --fail || echo_and_exit "unable to download $url"
    echo "unzipping $output_name ..."
    tar -xf "$output_name" || unzip "$output_name" || exit 1
    touch "$output_dir/unpacked.successfully" || exit 1
    rm "$output_name" || exit 1
  fi
}

generic_configure() {
  build_triple="${build_triple:-$(gcc -dumpmachine)}"
  local extra_configure_options="$1"
  if [[ -n $build_triple ]]; then extra_configure_options+=" --build=$build_triple"; fi
  do_configure "--host=$host_target --prefix=$x86_64_prefix --disable-shared --enable-static $extra_configure_options"
}

# params: url, optional "english name it will unpack to"
generic_download_and_make_and_install() {
  local url="$1"
  local english_name="$2"
  if [[ -z $english_name ]]; then
    english_name=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
  fi
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  cd $english_name || exit "unable to cd, may need to specify dir it will unpack to as parameter"
  generic_configure "$extra_configure_options"
  do_make_and_make_install
  cd ..
}

do_git_checkout_and_make_install() {
  local url=$1
  local git_checkout_name=$(basename $url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  do_git_checkout $url $git_checkout_name
  cd $git_checkout_name
    generic_configure_make_install
  cd ..
}

generic_configure_make_install() {
  if [ $# -gt 0 ]; then
    echo "cant pass parameters to this method today, they'd be a bit ambiguous"
    echo "The following arguments where passed: ${@}"
    exit 1
  fi
  generic_configure # no parameters, force myself to break it up if needed
  do_make_and_make_install
}

gen_ld_script() {
  lib=$x86_64_prefix/lib/$1
  lib_s="$2"
  if [[ ! -f $x86_64_prefix/lib/lib$lib_s.a ]]; then
    echo "Generating linker script $lib: $2 $3"
    mv -f $lib $x86_64_prefix/lib/lib$lib_s.a
    echo "GROUP ( -l$lib_s $3 )" > $lib
  fi
}

build_dlfcn() {
  do_git_checkout https://github.com/dlfcn-win32/dlfcn-win32 dlfcn-win32_git
  cd dlfcn-win32_git
    do_cmake_and_install "-DBUILD_TESTS=0"
  cd ..
}

build_bzip2() {
  download_and_unpack_file https://gitlab.com/bzip2/bzip2/-/archive/master/bzip2-master.tar.gz
  cd bzip2-master
    do_cmake "-B build -GNinja -DENABLE_APP=0 -DENABLE_TESTS=0 -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_STATIC_LIB=1 -DENABLE_SHARED_LIB=0" #-DENABLE_STATIC_LIB_IS_PIC=0
    do_ninja_and_ninja_install
    mv $x86_64_prefix/lib/libbz2_static.a $x86_64_prefix/lib/libbz2.a
  cd ..
}

build_liblzma() {
  download_and_unpack_file https://sourceforge.net/projects/lzmautils/files/xz-5.8.3.tar.xz
  cd xz-5.8.3
    do_cmake "-B build -GNinja -DXZ_NLS=0 -DXZ_DOC=0 -DZ_TOOL_SCRIPTS=0 -DXZ_TOOL_LZMAINFO=0 -DXZ_TOOL_LZMADEC=0 -DXZ_TOOL_XZDEC=0 -DXZ_TOOL_XZ=0 -DXZ_TOOL_SYMLINKS=0"
    do_ninja_and_ninja_install
  cd ..
}

build_zlib() {
  download_and_unpack_file https://github.com/madler/zlib/archive/refs/tags/v1.3.2.tar.gz zlib-1.3.2
  cd zlib-1.3.2
    sed -i.bak 's/set(zlib_static_suffix "s").*/set(zlib_static_suffix "")/' CMakeLists.txt
    do_cmake "-B build -GNinja -DZLIB_BUILD_TESTING=0 -DZLIB_BUILD_SHARED=0 -DZLIB_INSTALL_COMPAT_DLL=0"
    do_ninja_and_ninja_install
  cd ..
}

build_iconv() {
  download_and_unpack_file https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.19.tar.gz
  cd libiconv-1.19
    generic_configure "--disable-nls"
    do_make "install-lib" # No need for 'do_make_install', because 'install-lib' already has install-instructions.
  cd ..
}

build_brotli() {
  do_git_checkout https://github.com/google/brotli.git brotli_git v1.2.0
  cd brotli_git
    do_cmake "-B build -G Ninja"
    do_ninja_and_ninja_install
  cd ..
}  
  
build_zstd() {  
  do_git_checkout https://github.com/facebook/zstd.git zstd_git v1.5.7
  cd zstd_git
    do_cmake "-S build/cmake -B build -G Ninja -DZSTD_BUILD_SHARED=OFF -DZSTD_USE_STATIC_RUNTIME=ON -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF"
    do_ninja_and_ninja_install
  cd ..
 } 
  
build_sdl2() {
  download_and_unpack_file https://www.libsdl.org/release/SDL2-2.32.10.tar.gz
  cd SDL2-2.32.10
    apply_patch file://$patch_dir/SDL2-2.32.10_lib-only.diff
    if [[ ! -f configure.bak ]]; then
      sed -i.bak "s/ -mwindows//" configure # Allow ffmpeg to output anything to console.
    fi
    export CFLAGS="$CFLAGS -DDECLSPEC="  # avoid SDL trac tickets 939 and 282 [broken shared builds]
    if [[ $compiler_flavors == "native" ]]; then
      unset PKG_CONFIG_LIBDIR # Allow locally installed things for native builds; libpulse-dev is an important one otherwise no audio for most Linux
    fi
    generic_configure "--bindir=$bin_path"
    do_make_and_make_install
    if [[ $compiler_flavors == "native" ]]; then
      export PKG_CONFIG_LIBDIR=
    fi
    if [[ ! -f $bin_path/$host_target-sdl2-config ]]; then
      mv "$bin_path/sdl2-config" "$bin_path/$host_target-sdl2-config" # At the moment FFmpeg's 'configure' doesn't use 'sdl2-config', because it gives priority to 'sdl2.pc', but when it does, it expects 'i686-w64-mingw32-sdl2-config' in 'mingw-w64-i686/bin'.
    fi
    mkdir $x86_64_prefix/lib/cmake/SDL2 
    cp sdl2-config.cmake $x86_64_prefix/lib/cmake/SDL2 
    reset_cflags
  cd ..
}

build_amd_amf_headers() {
  # was https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git too big
  # or https://github.com/DeadSix27/AMF smaller
  # but even smaller!
  do_git_checkout https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git amf_headers_git
  cd amf_headers_git
    if [ ! -f "already_installed" ]; then
      #rm -rf "./Thirdparty" # ?? plus too chatty...
      if [ ! -d "$x86_64_prefix/include/AMF" ]; then
        mkdir -p "$x86_64_prefix/include/AMF"
      fi
      cp -av "amf/public/include/." "$x86_64_prefix/include/AMF"
      touch "already_installed"
    fi
  cd ..
}

build_nv_headers() {
  if [[ $ffmpeg_git_checkout_version == *"n6.0"* ]] || [[ $ffmpeg_git_checkout_version == *"n5"* ]] || [[ $ffmpeg_git_checkout_version == *"n4"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
    # nv_headers for old versions
    do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git nv-codec-headers_git n12.0.16.1
  else
    do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git
  fi
  cd nv-codec-headers_git
    do_make_install "PREFIX=$x86_64_prefix" # just copies in headers
  cd ..
}

build_libvpl () {
  do_git_checkout https://github.com/intel/libvpl.git libvpl_git
  cd libvpl_git
    if [ "$bits_target" = "32" ]; then
      apply_patch "https://raw.githubusercontent.com/msys2/MINGW-packages/master/mingw-w64-libvpl/0003-cmake-fix-32bit-install.patch" -p1
    fi
    do_cmake "-B build -GNinja -DINSTALL_EXAMPLES=OFF -DINSTALL_DEV=ON -DBUILD_EXPERIMENTAL=OFF" 
    do_ninja_and_ninja_install
    sed -i.bak "s/Libs: .*/& -lstdc++/" "$PKG_CONFIG_PATH/vpl.pc"
  cd ..
}

install_libtensorflow() { 
  if [[ ! -e Tensorflow ]]; then
    mkdir Tensorflow
    cd Tensorflow
	 # wget https://storage.googleapis.com/tensorflow/libtensorflow/libtensorflow-gpu-windows-x86_64-2.10.0.zip # comment in/out for gpu; requires cudart64_110.dll & tensorflow.dll
	 wget https://storage.googleapis.com/tensorflow/versions/2.18.1/libtensorflow-cpu-windows-x86_64.zip # comment in/out for cpu; requires tensorflow.dll
	 unzip -o libtensorflow-*.zip -d $x86_64_prefix
	 rm libtensorflow-*.zip
	 mkdir ../../redist
	 cp $x86_64_prefix/lib/tensorflow.dll ../../redist 
    cd ..
  else echo "Tensorflow already installed"
  fi
}

build_glib() {
  # generic_download_and_make_and_install  https://ftp.gnu.org/pub/gnu/gettext/gettext-0.26.tar.gz
  # download_and_unpack_file  https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz # also dep
  # cd libffi-3.5.2
    # apply_patch file://$patch_dir/libffi.patch -p1 
    # generic_configure_make_install
  # cd ..
  do_git_checkout https://github.com/GNOME/glib.git glib_git 
  activate_meson
  cd glib_git
    local meson_options="setup --force-fallback-for=pcre2,libffi,proxy-libintl -Dman-pages=disabled -Dsysprof=disabled -Dglib_debug=disabled -Dtests=false --wrap-mode=default . build" #-Dforce_posix_threads=true
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    if [[ $compiler_flavors == "native" ]]; then
      sed -i.bak 's/-lglib-2.0.*$/-lglib-2.0 -lm -liconv/' $PKG_CONFIG_PATH/glib-2.0.pc
    else
      sed -i.bak 's/-lglib-2.0.*$/-lglib-2.0 -lintl -lws2_32 -lwinmm -lm -liconv -lole32/' $PKG_CONFIG_PATH/glib-2.0.pc
    fi
  deactivate
  cd ..
}

build_lensfun() {
  build_glib
  do_git_checkout https://github.com/lensfun/lensfun.git lensfun_git
  cd lensfun_git
    export CXXFLAGS="$CXXFLAGS -DGLIB_STATIC_COMPILATION"
    do_cmake "-DBUILD_STATIC=on -DCMAKE_INSTALL_DATAROOTDIR=$x86_64_prefix -DBUILD_TESTS=off -DBUILD_DOC=off -DINSTALL_HELPER_SCRIPTS=off -DINSTALL_PYTHON_MODULE=OFF"
    do_make_and_make_install
    sed -i.bak 's/-llensfun/-llensfun -lstdc++/' "$PKG_CONFIG_PATH/lensfun.pc"
    reset_cxxflags
  cd ..
}

build_libpsl () {
  export CFLAGS="-DPSL_STATIC"
  download_and_unpack_file https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz  
  cd libpsl-0.21.5
    generic_configure "--disable-nls --disable-rpath --disable-gtk-doc-html --disable-man --disable-runtime"
    do_make_and_make_install
    sed -i.bak "s/Libs: .*/& -lidn2 -lunistring -lws2_32 -liconv/" $PKG_CONFIG_PATH/libpsl.pc
  reset_cflags
  cd ..
}
 
build_nghttp2 () { 
  export CFLAGS="-DNGHTTP2_STATICLIB"
  download_and_unpack_file https://github.com/nghttp2/nghttp2/releases/download/v1.69.0/nghttp2-1.69.0.tar.gz
  cd nghttp2-1.69.0
    do_cmake "-B build -DENABLE_LIB_ONLY=1 -DBUILD_SHARED_LIBS=0 -DBUILD_STATIC_LIBS=1 -GNinja"
    do_ninja_and_ninja_install
  reset_cflags
  cd ..
}
 
build_curl () { 
  generic_download_and_make_and_install https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.gz
  build_zstd
  build_brotli
  build_libpsl
  build_nghttp2
  local config_options=""
  if [[ $compiler_flavors == "native" ]]; then
    local config_options+="-DGNUTLS_INTERNAL_BUILD" 
  fi  
  export CPPFLAGS+="$CPPFLAGS -DNGHTTP2_STATICLIB -DPSL_STATIC $config_options"
  do_git_checkout https://github.com/curl/curl.git curl_git curl-8_20_0
  cd curl_git 
    if [[ $compiler_flavors != "native" ]]; then
      generic_configure "--with-libssh2 --with-libpsl --with-libidn2 --disable-debug --enable-hsts --with-brotli --enable-versioned-symbols --enable-sspi --with-schannel"
    else
      generic_configure "--with-gnutls --with-libssh2 --with-libpsl --with-libidn2 --disable-debug --enable-hsts --with-brotli --enable-versioned-symbols" # untested on native
    fi
    do_make_and_make_install
  reset_cppflags
  cd ..
}

build_lz4 () {
  download_and_unpack_file https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz
  cd lz4-1.10.0
    do_cmake "-S build/cmake -B build -GNinja -DBUILD_STATIC_LIBS=1"
    do_ninja_and_ninja_install
  cd .. 
}

 build_libarchive () {
  build_lz4
  download_and_unpack_file https://github.com/libarchive/libarchive/releases/download/v3.8.7/libarchive-3.8.7.tar.gz
  cd libarchive-3.8.7
    # do_cmake "-B build -GNinja -DENABLE_TEST=0 -DENABLE_NETTLE=1 -DENABLE_OPENSSL=0 -DENABLE_ICONV=0 -DENABLE_PCRE2POSIX=0 -DENABLE_PCREPOSIX=0 -DMSVC_USE_STATIC_CRT=1"
    # do_ninja_and_ninja_install
    generic_configure "--with-nettle --bindir=$x86_64_prefix/bin --without-openssl --without-iconv --disable-posix-regex-lib"
    do_make_and_make_install
  cd ..
}

build_gif() {
  download_and_unpack_file https://sourceforge.net/projects/giflib/files/giflib-5.x/giflib-5.2.2.tar.gz giflib-5.2.2
  if [[ ! -f giflib-5.2.2/meson.build ]]; then
    wget https://wrapdb.mesonbuild.com/v2/giflib_5.2.2-3/get_patch
    unzip -o get_patch && rm get_patch
  fi
  activate_meson
  cd giflib-5.2.2
    local meson_options="setup -Dtests=disabled -Dprogs=disabled . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
  deactivate
  cd ..
}

build_libleptonica() {
  build_gif
  do_git_checkout https://github.com/DanBloomberg/leptonica.git leptonica_git
  cd leptonica_git
    generic_configure "--disable-programs CPPFLAGS=-DOPJ_STATIC"
    do_make_and_make_install
    sed -i.bak 's/libopenjp2.*/libopenjp2 libwebpdecoder libwebpdemux libsharpyuv/' $PKG_CONFIG_PATH/lept.pc
  cd ..
}

build_glut() {
  download_and_unpack_file https://github.com/freeglut/freeglut/releases/download/v3.8.0/freeglut-3.8.0.tar.gz
  cd freeglut-3.8.0
    do_cmake "-B build -GNinja -DFREEGLUT_BUILD_DEMOS=0 -DFREEGLUT_BUILD_SHARED_LIBS=0 -DFREEGLUT_INSTALL_MAN_PAGES=0 -DFREEGLUT_REPLACE_GLUT=1 -DFREEGLUT_BUILD_STATIC_LIBS=1"
    do_ninja_and_ninja_install
    sed -i.bak "s/-lfreeglut.*/-lglut/" $PKG_CONFIG_PATH/glut.pc
  cd ..
}

build_deflate() {
  do_git_checkout https://github.com/ebiggers/libdeflate libdeflate_git
  cd libdeflate_git
    do_cmake "-B build -GNinja -DLIBDEFLATE_BUILD_SHARED_LIB=0 -DLIBDEFLATE_BUILD_STATIC_LIB=1 -DLIBDEFLATE_USE_SHARED_LIB=0 -DLIBDEFLATE_BUILD_GZIP=0 -DLIBDEFLATE_INSTALL=1"
    do_ninja_and_ninja_install
  cd ..
}

build_libtiff() {
  build_glut
  build_deflate
  download_and_unpack_file http://download.osgeo.org/libtiff/tiff-4.7.1.tar.gz
  cd tiff-4.7.1
    generic_configure "--disable-cxx --disable-tests --disable-tools --disable-contrib --disable-docs --disable-sphinx"
    do_make_and_make_install
  cd ..
    sed -i.bak 's/libzstd.*/libzstd libwebp libsharpyuv libpng libpng16 libturbojpeg glut /' $PKG_CONFIG_PATH/libtiff-4.pc
    sed -i 's/-lm.*/-lm -lopengl32/' $PKG_CONFIG_PATH/libtiff-4.pc
    sed -i 's/-I${includedir}.*/-I${includedir} -DFREEGLUT_STATIC/' $PKG_CONFIG_PATH/libtiff-4.pc
  #cd ..
}

build_libtesseract() {
  build_libtiff
  build_libleptonica   
  build_libarchive
  do_git_checkout https://github.com/tesseract-ocr/tesseract.git tesseract_git
  cd tesseract_git
	sed -i.bak 's/Ws2_32} ${LIB_pthread}).*/ws2_32} ${LIB_pthread})/' CMakeLists.txt
	sed -i 's/Ws2_32 Ws2_32).*/ws2_32 ws2_32)/' CMakeLists.txt
    generic_configure "--enable-openmp --with-archive --disable-graphics --disable-tessdata-prefix --with-curl LIBLEPT_HEADERSDIR=$x86_64_prefix/include --datadir=$x86_64_prefix/bin CPPFLAGS=-DCURL_STATICLIB"
    do_make_and_make_install
    sed -i.bak 's/lept.*/lept libarchive liblzma libtiff-4 libcurl/' $PKG_CONFIG_PATH/tesseract.pc
    sed -i 's/-lnghttp2.*/-lnghttp2 -lstdc++/' $PKG_CONFIG_PATH/tesseract.pc
    sed -i 's/-lpthread.*/-pthread -lgomp/' $PKG_CONFIG_PATH/tesseract.pc
    sed -i 's/-I${includedir}.*/-I\${includedir} -fopenmp/' $PKG_CONFIG_PATH/tesseract.pc
    mkdir $HOME/sandbox/redist
    cp tesseract.exe $HOME/sandbox/redist
    if [[ ! -f $x86_64_prefix/bin/tessdata/eng.traineddata ]]; then
      mkdir -p $x86_64_prefix/bin/tessdata
	 wget https://github.com/tesseract-ocr/tessdata/raw/ced78752cc61322fb554c280d13360b35b8684e4/eng.traineddata
	 wget https://github.com/tesseract-ocr/tessdata/raw/refs/heads/main/osd.traineddata
      cp -rf {eng,osd}.traineddata $x86_64_prefix/bin/tessdata/ 
    fi
  cd ..
}

build_libzimg() {
  do_git_checkout_and_make_install https://github.com/sekrit-twc/zimg.git zimg_git
}

build_libopenjpeg() {
  do_git_checkout https://github.com/uclouvain/openjpeg.git openjpeg_git
  cd openjpeg_git
    do_cmake_and_install "-DBUILD_CODEC=0"
  cd ..
}

build_glew() {
  download_and_unpack_file https://sourceforge.net/projects/glew/files/glew/2.3.1/glew-2.3.1.tgz glew-2.3.1
  cd glew-2.3.1/build
    local cmake_params=""
    if [[ $compiler_flavors != "native" ]]; then
      cmake_params+=" -DWIN32=1"
    fi
    do_cmake_from_build_dir ./cmake "$cmake_params"
    do_make_and_make_install
  cd ../..
}

build_glfw() {
  download_and_unpack_file https://github.com/glfw/glfw/releases/download/3.4/glfw-3.4.zip glfw-3.4
  cd glfw-3.4
    do_cmake_and_install
  cd ..
}

build_libjpeg_turbo() {
  download_and_unpack_file https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.1.4.1/libjpeg-turbo-3.1.4.1.tar.gz libjpeg-turbo-3.1.4.1
  cd libjpeg-turbo-3.1.4.1
    local cmake_params="-DENABLE_SHARED=0 -DCMAKE_ASM_NASM_COMPILER=yasm -DWITH_SIMD=1" #-DWITH_TESTS=0 -DWITH_TOOLS=0 -DWITH_CRT_DLL=0
    if [[ $compiler_flavors != "native" ]]; then
      cmake_params+=" -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake"
      local target_proc=AMD64
      if [ "$bits_target" = "32" ]; then
        target_proc=X86
      fi
      cat > toolchain.cmake << EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ${target_proc})
set(CMAKE_C_COMPILER ${cross_prefix}gcc)
set(CMAKE_RC_COMPILER ${cross_prefix}windres)
EOF
    fi
    do_cmake "-B build -GNinja $cmake_params"
    do_ninja_and_ninja_install
  cd ..
}

build_libpng() {
  download_and_unpack_file https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.58.tar.gz libpng-1.6.58
  cd libpng-1.6.58
    do_cmake "-B build -GNinja -DPNG_SHARED=0 -DPNG_TESTS=0"
    do_ninja_and_ninja_install
  cd ..
}

build_libwebp() {
  build_deflate
  build_gif
  do_git_checkout https://chromium.googlesource.com/webm/libwebp.git libwebp_git
  cd libwebp_git
    export LIBPNG_CONFIG="$x86_64_prefix/bin/libpng-config --static" # LibPNG somehow doesn't get autodetected
    generic_configure "--disable-wic"
    do_make_and_make_install
    unset LIBPNG_CONFIG
    sed -i.bak 's/-I${includedir}.*/-I${includedir} -DFREEGLUT_STATIC/' $PKG_CONFIG_PATH/lib{webp,webpmux,webpdemux,webpdecoder,sharpyuv}.pc
  cd ..
}

build_harfbuzz() {
  do_git_checkout https://github.com/harfbuzz/harfbuzz.git harfbuzz_git 9c6b699 # 11.0.0+ harfbuzz freetype circular depends hack broken per commit https://github.com/harfbuzz/harfbuzz/commit/628b868f44acce749adc08ff61f2d9c19c9e2bbe
  activate_meson
  build_freetype
  cd harfbuzz_git
    if [[ ! -f DUN ]]; then
      local meson_options="setup -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled . build"
      if [[ $compiler_flavors != "native" ]]; then
        # get_local_meson_cross_with_propeties 
        meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
        do_meson "$meson_options"      
      else
        generic_meson "$meson_options"
      fi
      do_ninja_and_ninja_install	   
      touch DUN
    fi
  cd ..
  build_freetype # with harfbuzz now
  deactivate
  sed -i.bak 's/-lfreetype.*/-lfreetype -lbz2/' "$PKG_CONFIG_PATH/freetype2.pc"
}

build_freetype() {
  do_git_checkout https://github.com/freetype/freetype.git freetype_git VER-2-14-3
  cd freetype_git
    local config_options=""
    if [[ -e $PKG_CONFIG_PATH/harfbuzz.pc ]]; then
      local config_options+=" -Dharfbuzz=enabled" 
    fi	
    local meson_options="setup $config_options . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
  cd ..
}

build_libxml2() {
  download_and_unpack_file https://gitlab.gnome.org/GNOME/libxml2/-/archive/v2.15.3/libxml2-v2.15.3.tar.gz
  cd libxml2-v2.15.3
    do_cmake "-B build -GNinja -DLIBXML2_WITH_HTTP=0 -DLIBXML2_WITH_PYTHON=0 -DLIBXML2_WITH_TESTS=0"
    do_ninja_and_ninja_install
  cd ..
}

build_libvmaf() {
  do_git_checkout https://github.com/Netflix/vmaf.git vmaf_git
  activate_meson
  cd vmaf_git/libvmaf
    local meson_options="setup -Denable_float=true -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    sed -i.bak "s/Libs: .*/& -lstdc++/" $PKG_CONFIG_PATH/libvmaf.pc
  deactivate
  cd ../..
}

build_fontconfig() {
  do_git_checkout https://gitlab.freedesktop.org/fontconfig/fontconfig.git fontconfig_git
  activate_meson
  cd fontconfig_git
    local meson_options="setup -Ddoc=disabled -Dtests=disabled -Diconv=enabled -Dxml-backend=libxml2 . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    sed -i.bak "s/Libs: .*/& -lstdc++/" $PKG_CONFIG_PATH/fontconfig.pc
  deactivate
  cd ..
}

build_gmp() {
  download_and_unpack_file https://ftp.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz
  cd gmp-6.3.0
    generic_configure "ABI=$bits_target CFLAGS=-std=c18 CC_FOR_BUILD=/usr/bin/gcc" # needed to build and for nettle/gnutls to see it
    do_make_and_make_install
    # make check
  cd ..
}

build_libnettle() {
  download_and_unpack_file https://ftp.gnu.org/gnu/nettle/nettle-4.0.tar.gz
  cd nettle-4.0
    generic_configure "--disable-openssl --disable-documentation --libdir=$x86_64_prefix/lib CFLAGS=-std=c18" # c18 needed to build
    do_make_and_make_install
  cd ..
}

build_unistring() {
  generic_download_and_make_and_install https://ftp.gnu.org/gnu/libunistring/libunistring-1.4.2.tar.gz
}

build_libidn2() {
  download_and_unpack_file https://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz
  cd libidn2-2.3.8
    generic_configure "--disable-doc --disable-rpath --disable-nls --disable-gtk-doc-html --disable-fast-install"
    do_make_and_make_install 
  cd ..
}

build_openssl-3.0.8() {
  download_and_unpack_file https://www.openssl.org/source/openssl-3.0.8.tar.gz openssl-3.0.8
  if [[ ! -f openssl-3.0.8/meson.build ]]; then
    wget https://wrapdb.mesonbuild.com/v2/openssl_3.0.8-3/get_patch
    unzip -o get_patch && rm get_patch
  fi
  activate_meson
  cd openssl-3.0.8
    local meson_options="setup -Dasm=disabled . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    deactivate
  cd ..
}

build_gnutls() {
  download_and_unpack_file https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.13.tar.xz
  cd gnutls-3.8.13
    export CFLAGS="-Wno-int-conversion"
    local config_options=""
    if [[ $compiler_flavors != "native" ]]; then
      local config_options+=" --disable-non-suiteb-curves" 
    fi	
    generic_configure "--disable-cxx --disable-doc --disable-tools --disable-tests --disable-nls --disable-rpath --disable-libdane --disable-gcc-warnings --disable-code-coverage
      --without-p11-kit --with-idn --without-tpm --with-included-unistring --with-included-libtasn1 -disable-gtk-doc-html --with-brotli $config_options"
    do_make_and_make_install
    reset_cflags
    if [[ $compiler_flavors != "native"  ]]; then
      sed -i.bak 's/-lgnutls.*/-lgnutls -lcrypt32 -lnettle -lhogweed -lgmp -liconv -lunistring/' $PKG_CONFIG_PATH/gnutls.pc
      if [[ $OSTYPE == darwin* ]]; then
        sed -i.bak 's/-lgnutls.*/-lgnutls -framework Security -framework Foundation/' $PKG_CONFIG_PATH/gnutls.pc
      fi
    fi
  cd ..
}

build_flac () {
  do_git_checkout https://github.com/xiph/flac.git flac_git 
  cd flac_git
    do_cmake "-B build -DINSTALL_MANPAGES=OFF -GNinja"
    do_ninja_and_ninja_install
  cd ..
}

build_openmpt () {
  build_flac
  do_git_checkout https://github.com/OpenMPT/openmpt.git openmpt_git OpenMPT-1.32.10.00
  cd openmpt_git
    do_make_and_make_install "PREFIX=$x86_64_prefix CONFIG=mingw-w64 WINDOWS_ARCH=amd64 DYNLINK=0 SHARED_LIB=0 STATIC_LIB=1 EXAMPLES=0 TEST=0 \
	MODERN=0 NO_ZLIB=0 NO_MPG123=0 NO_OGG=0 NO_VORBIS=0 NO_VORBISFILE=0 NO_SDL2=0 NO_SNDFILE=0 NO_FLAC=0 OPENMPT123=0 \
	LOCAL_ZLIB=0 LOCAL_MPG123=0 LOCAL_OGG=0 LOCAL_VORBIS=0 CXXSTDLIB_PCLIBSPRIVATE='-lstdc++'" # OPENMPT123=1 >>> fail
  cd ..
}

build_libogg() {
  do_git_checkout_and_make_install https://github.com/xiph/ogg.git
}

build_libvorbis() {
  do_git_checkout https://github.com/xiph/vorbis.git
  cd vorbis_git
    generic_configure "--disable-docs --disable-examples --disable-oggtest"
    do_make_and_make_install
  cd ..
}

build_libopus() {
  do_git_checkout https://github.com/xiph/opus.git opus_git origin/main
  cd opus_git
    generic_configure "--disable-doc --disable-extra-programs --disable-stack-protector"
    do_make_and_make_install
  cd ..
}

build_libspeexdsp() {
  do_git_checkout https://github.com/xiph/speexdsp.git
  cd speexdsp_git
    generic_configure "--disable-examples"
    do_make_and_make_install
  cd ..
}

build_libspeex() {
  do_git_checkout https://github.com/xiph/speex.git
  cd speex_git
    export SPEEXDSP_CFLAGS="-I$x86_64_prefix/include"
    export SPEEXDSP_LIBS="-L$x86_64_prefix/lib -lspeexdsp" # 'configure' somehow can't find SpeexDSP with 'pkg-config'.
    generic_configure "--disable-binaries" # If you do want the libraries, then 'speexdec.exe' needs 'LDFLAGS=-lwinmm'.
    do_make_and_make_install
    unset SPEEXDSP_CFLAGS
    unset SPEEXDSP_LIBS
  cd ..
}

build_libtheora() {
  do_git_checkout https://github.com/xiph/theora.git
  cd theora_git
    generic_configure "--disable-doc --disable-spec --disable-oggtest --disable-vorbistest --disable-examples --disable-asm" # disable asm: avoid [theora @ 0x1043144a0]error in unpack_block_qpis in 64 bit... [OK OS X 64 bit tho...]
    do_make_and_make_install
  cd ..
}

build_libsndfile() {
  do_git_checkout https://github.com/libsndfile/libsndfile.git
  cd libsndfile_git
    generic_configure "--disable-sqlite --disable-external-libs --disable-full-suite"
    do_make_and_make_install
    if [ "$1" = "install-libgsm" ]; then
      if [[ ! -f $x86_64_prefix/lib/libgsm.a ]]; then
        install -m644 src/GSM610/gsm.h $x86_64_prefix/include/gsm.h || exit 1
        install -m644 src/GSM610/.libs/libgsm.a $x86_64_prefix/lib/libgsm.a || exit 1
      else
        echo "already installed GSM 6.10 ..."
      fi
    fi
  cd ..
}

build_mpg123() {
  download_and_unpack_file https://sourceforge.net/projects/mpg123/files/mpg123/1.33.6/mpg123-1.33.6.tar.bz2
  cd mpg123-1.33.6
    generic_configure_make_install
  cd ..
}

build_lame() {
  do_svn_checkout https://svn.code.sf.net/p/lame/svn/trunk/lame lame_svn r6527 # r6531-r6528 fail https://sourceforge.net/p/lame/svn/6531/log/?path=/trunk
  cd lame_svn
    generic_configure "--enable-nasm --enable-libmpg123"
    do_make_and_make_install
    sed -i.bak 's/-lmp3lame.*/-lmp3lame\nLibs.private: -lm -lmpg123 -lshlwapi/' $PKG_CONFIG_PATH/lame.pc
  cd ..
}

build_twolame() {
  do_git_checkout https://github.com/njh/twolame.git twolame_git "origin/main"
  cd twolame_git
    if [[ ! -f Makefile.am.bak ]]; then # Library only, front end refuses to build for some reason with git master
      sed -i.bak "/^SUBDIRS/s/ frontend.*//" Makefile.am || exit 1
    fi
    cpu_count=1 # maybe can't handle it http://betterlogic.com/roger/2017/07/mp3lame-woe/ comments
    generic_configure_make_install
    cpu_count=$original_cpu_count
    cat > $PKG_CONFIG_PATH/libtwolame.pc << EOF
prefix=$x86_64_prefix
exec_prefix=\$prefix/bin
libdir=\$prefix/lib
includedir=\$prefix/include

Name: libtwolame
Description: TwoLAME is an optimized MPEG Audio Layer 2 (MP2) encoder
Version: 0.4.0
Libs: -L\${libdir} -ltwolame
Libs.private: -lshlwapi -lmpg123
Cflags: -I\${includedir} -DLIBTWOLAME_STATIC
EOF
  cd ..
}

build_fdk-aac() {
local checkout_dir=fdk-aac_git
    if [[ ! -z $fdk_aac_git_checkout_version ]]; then
      checkout_dir+="_$fdk_aac_git_checkout_version"
      do_git_checkout "https://github.com/mstorsjo/fdk-aac.git" $checkout_dir "refs/tags/$fdk_aac_git_checkout_version"
    else
      do_git_checkout "https://github.com/mstorsjo/fdk-aac.git" $checkout_dir
    fi
  cd $checkout_dir
    if [[ ! -f "configure" ]]; then
      autoreconf -fiv || exit 1
    fi
    generic_configure_make_install
  cd ..
}

build_AudioToolboxWrapper() {
  do_git_checkout https://github.com/cynagenautes/AudioToolboxWrapper.git AudioToolboxWrapper_git
  cd AudioToolboxWrapper_git
    do_cmake "-B build -GNinja"
    do_ninja_and_ninja_install
    # i.e. You need to install iTunes, or be able to LoadLibrary("CoreAudioToolbox.dll"), for this to work.
    # test ffmpeg build can use it [ffmpeg -f lavfi -i sine=1000 -c aac_at -f mp4 -y NUL]
  cd ..
}

build_libopencore() {
  generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/opencore-amr/opencore-amr-0.1.6.tar.gz
  generic_download_and_make_and_install https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/vo-amrwbenc-0.1.3.tar.gz
}

build_libilbc() {
  do_git_checkout https://github.com/TimothyGu/libilbc.git libilbc_git
  cd libilbc_git
    do_cmake "-B build -GNinja"
    do_ninja_and_ninja_install
  cd ..
}

build_libmodplug() {
  do_git_checkout https://github.com/Konstanty/libmodplug.git
  cd libmodplug_git
    sed -i.bak 's/__declspec(dllexport)//' "$x86_64_prefix/include/libmodplug/modplug.h" #strip DLL import/export directives
    sed -i.bak 's/__declspec(dllimport)//' "$x86_64_prefix/include/libmodplug/modplug.h"
    if [[ ! -f "configure" ]]; then
      autoreconf -fiv || exit 1
      automake --add-missing || exit 1
    fi
    generic_configure_make_install # or could use cmake I guess
    echo "Cflags.private: -DMODPLUG_STATIC" >> $PKG_CONFIG_PATH/libmodplug.pc
  cd ..
}

build_libgme() {
  # do_git_checkout https://bitbucket.org/mpyne/game-music-emu.git
  download_and_unpack_file https://bitbucket.org/mpyne/game-music-emu/downloads/game-music-emu-0.6.3.tar.xz
  cd game-music-emu-0.6.3
    do_cmake_and_install "-DENABLE_UBSAN=0"
  cd ..
}

build_mingw_std_threads() {
  do_git_checkout https://github.com/meganz/mingw-std-threads.git # it needs std::mutex too :|
  cd mingw-std-threads_git
    cp *.h "$x86_64_prefix/include"
  cd ..
}

install_cudatoolkit() {
  if [[ ! -f cuda_13.3.0_610.43.02_linux.run ]]; then
    wget https://developer.download.nvidia.com/compute/cuda/13.3.0/local_installers/cuda_13.3.0_610.43.02_linux.run
  fi
  if [[ ! -f $HOME/sandbox/x86_64/bin/nvcc ]]; then
    chmod u+x cuda_13.3.0_610.43.02_linux.run && ./cuda_13.3.0_610.43.02_linux.run --toolkit --installpath=$HOME/sandbox/x86_64 --silent --no-man-page --tmpdir=/var/tmp
    echo 'export PATH=$HOME/sandbox/x86_64/bin:${PATH}' >> ~/.bashrc
    echo 'export PATH=$HOME/sandbox/x86_64/nvvm/bin:${PATH}' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/lib/wsl/lib:${LD_LIBRARY_PATH}' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=$HOME/sandbox/x86_64/lib64:${LD_LIBRARY_PATH}' >> ~/.bashrc			
    echo 'export CPATH=$HOME/sandbox/x86_64/targets/x86_64-linux/include:${CPATH}' >> ~/.bashrc
    source ~/.bashrc
    nvcc --version
  fi
} 

build_blas() {
  do_git_checkout https://github.com/OpenMathLib/OpenBLAS OpenBLAS_git cf62771
  cd OpenBLAS_git ### match your cpu in targetlists.txt and change -DTARGET accordingly ###
    do_cmake "-B build -GNinja -DTARGET=ZEN -DBUILD_STATIC_LIBS=1 -DUSE_OPENMP=1 -DBUILD_TESTING=0 -DBUILD_BENCHMARKS=0 -DBUILD_RELAPACK=1\
       -DBUILD_LAPACK_DEPRECATED=0 -DUSE_THREAD=1 -DUSE_LOCKING=0 -DGEMM_MULTITHREAD_THRESHOLD=$core_count -DBUILD_BFLOAT16=1"
    do_ninja_and_ninja_install
    sed -i.bak 's/-l${libnameprefix}openblas${libnamesuffix}${libsuffix}.*/-lopenblas\nLibs.private: -lgfortran -lgomp -pthread -lm/' $PKG_CONFIG_PATH/openblas.pc
  cd ..
}
  
build_whisper() {
  # build_openCL
  build_blas
  build_spriv-headers
  do_git_checkout https://github.com/ggml-org/whisper.cpp.git whisper_git v1.9.1
  cd whisper_git
    if [[ ! -f $HOME/sandbox/redist/ggml-large-v2-q8_0.bin ]]; then
      mkdir $HOME/sandbox/redist 
      cp ./models/for-tests-silero-v6.2.0-ggml.bin ./models/ggml-silero-v6.2.0.bin && mv ./models/ggml-silero-v6.2.0.bin $HOME/sandbox/redist/
      sh ./models/download-ggml-model.sh large-v2-q8_0 && mv ./models/ggml-large* $HOME/sandbox/redist
    fi
    if [[ $OSTYPE != darwin* ]]; then
      local config_options="1" 
    else
      local config_options="0" 
    fi # opencl meant for mobiles with adreno; vulkan, blas, cpu backends seem to all work together in ffmpeg, careful with march native/cpu specific flags in blas/whisper/ffmpeg break functionality even if GGML_NATIVE=0, blas requires cpu backend to work in all tests tried
    do_cmake "-B build -GNinja -DGGML_OPENMP=0 -DGGML_CCACHE=0 -DGGML_BLAS=1 -DGGML_BLAS_VENDOR=OpenBLAS -DGGML_CUDA=0 -DGGML_VULKAN="$config_options" -DGGML_VULKAN_VALIDATE=0 -DGGML_OPENCL=0 -DGGML_OPENCL_USE_ADRENO_KERNELS=0\
	-DWHISPER_BUILD_EXAMPLES=1 -DWHISPER_BUILD_TESTS=0 -DWHISPER_USE_SYSTEM_GGML=0 -DGGML_STATIC=1 -DGGML_CPU=1 -DGGML_NATIVE=1" # -DWHISPER_SDL2=1 -DSDL2_DIR=$x86_64_prefix/lib/cmake/SDL2" # needed to build all examples 
    do_ninja_and_ninja_install
    # sed -i "s/-I${includedir}.*/-I\${includedir} -fopenmp/" $PKG_CONFIG_PATH/whisper.pc  	
    if [[ $OSTYPE != darwin* ]]; then
      sed -i.bak 's/^\(Libs:\).*$/\1 -L${libdir} -lwhisper\nRequires: vulkan openblas\nLibs.private: -l:ggml.a -l:ggml-base.a -l:ggml-cpu.a -l:ggml-blas.a -l:ggml-vulkan.a -lstdc++ -pthread/' $PKG_CONFIG_PATH/whisper.pc
    else Cflags: -I${includedir}
      sed -i.bak 's/^\(Libs:\).*$/\1 -L${libdir} -lwhisper\nRequires: openblas\nLibs.private: -l:ggml.a -l:ggml-base.a -l:ggml-cpu.a -l:ggml-blas.a -lstdc++ -pthread/' $PKG_CONFIG_PATH/whisper.pc
    fi	
    # ffmpeg -i "%~1" -vn -af "whisper=model=C\\:/path/to/ggml-large-v2-q8_0.bin:vad_model=C\\:/path/to/ggml-silero-v6.2.0.bin:use_gpu=true:gpu_device=0:vad_min_silence_duration=1.0:vad_threshold=0.4:language=en:queue=5:destination=C\\:path/to/outputs/output.srt:format=srt" -loglevel debug -f null  "%~1"
 cd ..
}

build_openCL() {
  do_git_checkout https://github.com/KhronosGroup/OpenCL-Headers.git OpenCL-Headers_git e551385
  do_git_checkout https://github.com/KhronosGroup/OpenCL-ICD-Loader.git OpenCL-ICD-Loader_git b07d900
  cd OpenCL-Headers_git
    mkdir -p "$x86_64_prefix"/include/CL
    cp -r CL/* "$x86_64_prefix"/include/CL/
    cp OpenCL-Headers.pc.in $PKG_CONFIG_PATH/OpenCL-Headers.pc	
    sed -i "s|@PKGCONFIG_PREFIX@.*|$x86_64_prefix|" $PKG_CONFIG_PATH/OpenCL-Headers.pc
    sed -i "s|@OPENCL_INCLUDEDIR_PC@.*|$x86_64_prefix/include|" $PKG_CONFIG_PATH/OpenCL-Headers.pc	
    cd ../OpenCL-ICD-Loader_git
    do_cmake "-B build -GNinja -DOPENCL_ICD_LOADER_HEADERS_DIR=$x86_64_prefix/include\
	-DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=0 -DBUILD_TESTING=0 -DOPENCL_ICD_LOADER_BUILD_TESTING=0"
    do_ninja_and_ninja_install
    echo "exec_prefix=\${prefix}" >> $PKG_CONFIG_PATH/OpenCL.pc
    echo "includedir=\${prefix}/include/CL" >> $PKG_CONFIG_PATH/OpenCL.pc
    echo "Cflags: -I\${includedir}" >> $PKG_CONFIG_PATH/OpenCL.pc	
    sed -i.bak "s/-lOpenCL.*/-l:OpenCL.a/" $PKG_CONFIG_PATH/OpenCL.pc
    echo "Libs.private: -lole32 -lshlwapi -lcfgmgr32" >> $PKG_CONFIG_PATH/OpenCL.pc
  cd ..
}

build_opencv() {
  build_mingw_std_threads
  build_openCL
  # build_blas
  do_git_checkout https://github.com/opencv/opencv opencv_git 4.13.0
  cd opencv_git
    if [[ $OSTYPE != darwin* ]]; then
      local config_options="1" 
    else
      local config_options="0" 
    fi	
    do_cmake "-B build -GNinja -DWITH_FFMPEG=0 -DBUILD_TESTS=0 -DBUILD_PERF_TESTS=0 -DBUILD_ZLIB=0 -DBUILD_TIFF=0 -DBUILD_PNG=0 -DBUILD_WEBP=0 -DBUILD_JPEG=0 -DBUILD_OPENJPEG=0 -DBUILD_opencv_apps=0 -DBUILD_SHARED_LIBS=0 \
	-DOPENCV_GENERATE_PKGCONFIG=1 -DOPENCV_ENABLE_NONFREE=1 -DWITH_VULKAN="$config_options" -DWITH_OPENMP=1 -DWITH_OPENCL=1 -DWITH_LAPACK=0" # BUILD_PACKAGE=0 to find already built package, otherwise builds from 3rdparty...
    do_ninja_and_ninja_install # WITH_LAPACK=1 requires blas be built with NOFORTRAN and frei0r cannot use opencv if WITH_LAPACK=1
    sed -i.bak 's/-lopencv_core4130.*/& -lstdc++/' $PKG_CONFIG_PATH/opencv4.pc
    sed -i "s/-lpthread.*/-pthread -l:OpenCL.a/" $PKG_CONFIG_PATH/opencv4.pc
    sed -i "s/-I${includedir}.*/-I\${includedir} -fopenmp/" $PKG_CONFIG_PATH/opencv4.pc
  cd ..
}

build_libbluray() {
  do_git_checkout https://code.videolan.org/videolan/libbluray.git
  activate_meson
  cd libbluray_git
    apply_patch "https://raw.githubusercontent.com/m-ab-s/mabs-patches/master/libbluray/0001-dec-prefix-with-libbluray-for-now.patch" -p1
    local meson_options="setup -Denable_examples=false -Dbdj_jar=disabled --wrap-mode=default . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install # "CPPFLAGS=\"-Ddec_init=libbr_dec_init\""
      sed -i.bak 's/-lbluray.*/-lbluray -lstdc++ -lssp -lgdi32/' "$PKG_CONFIG_PATH/libbluray.pc"
  deactivate
  cd ..
}

build_libbs2b() {
  download_and_unpack_file https://downloads.sourceforge.net/project/bs2b/libbs2b/3.1.0/libbs2b-3.1.0.tar.gz
  cd libbs2b-3.1.0
    apply_patch file://$patch_dir/libbs2b.patch
    sed -i.bak "s/AC_FUNC_MALLOC//" configure.ac # #270
    export LIBS=-lm # avoid pow failure linux native
    generic_configure_make_install
    unset LIBS
  cd ..
}

build_libsoxr() {
  do_git_checkout https://github.com/chirlu/soxr.git soxr_git
  cd soxr_git
    do_cmake_and_install "-DWITH_OPENMP=1 -DBUILD_TESTS=0 -DBUILD_EXAMPLES=0"
    cat > $PKG_CONFIG_PATH/libsoxr.pc << EOF
prefix=$x86_64_prefix
exec_prefix=\$prefix/bin
libdir=\$prefix/lib
includedir=\$prefix/include

Name: libsoxr
Description: The SoX Resampler library libsoxr performs one-dimensional sample-rate conversion
Version: 0.1.3
Libs: -L\${libdir} -lsoxr 
Libs.private: -lgomp
Cflags: -I\${includedir} -fopenmp
EOF
  cd ..
}

build_libflite() {
  do_git_checkout https://github.com/festvox/flite.git flite_git
  cd flite_git
    apply_patch file://$patch_dir/flite-2.1.0_mingw-w64-fixes.patch
    if [[ ! -f main/Makefile.bak ]]; then									
    sed -i.bak "s/cp -pd/cp -p/" main/Makefile # friendlier cp for OS X
    fi
    generic_configure "--bindir=$x86_64_prefix/bin --with-audio=none" 
    do_make
    if [[ ! -f $x86_64_prefix/lib/libflite.a ]]; then
      cp -rf ./build/x86_64-mingw32/lib/libflite* $x86_64_prefix/lib/ 
      cp -rf include $x86_64_prefix/include/flite 
      # cp -rf ./bin/*.exe $x86_64_prefix/bin # if want .exe's uncomment
    fi
  cd ..
}

build_libsnappy() {
  do_git_checkout https://github.com/google/snappy.git snappy_git # got weird failure once 1.1.8
  cd snappy_git
    do_cmake_and_install "-DBUILD_BINARY=OFF -DSNAPPY_BUILD_TESTS=OFF -DSNAPPY_BUILD_BENCHMARKS=OFF" # extra params from deadsix27 and from new cMakeLists.txt content
    rm -f $x86_64_prefix/lib/libsnappy.dll.a # unintall shared :|
  cd ..
}

build_vamp_plugin() {
  download_and_unpack_file https://github.com/vamp-plugins/vamp-plugin-sdk/archive/refs/tags/vamp-plugin-sdk-v2.10.zip vamp-plugin-sdk-vamp-plugin-sdk-v2.10
  cd vamp-plugin-sdk-vamp-plugin-sdk-v2.10
    apply_patch file://$patch_dir/vamp-plugin-sdk-2.10_static-lib.diff
    if [[ $compiler_flavors != "native" && ! -f src/vamp-sdk/PluginAdapter.cpp.bak ]]; then
      sed -i.bak "s/#include <mutex>/#include <mingw.mutex.h>/" src/vamp-sdk/PluginAdapter.cpp
    fi
    if [[ ! -f configure.bak ]]; then # Fix for "'M_PI' was not declared in this scope" (see https://stackoverflow.com/a/29264536).
      sed -i.bak "s/c++11/gnu++11/" configure
      sed -i.bak "s/c++11/gnu++11/" Makefile.in
    fi
    do_configure "--host=$host_target --prefix=$x86_64_prefix --disable-programs"
    do_make "install-static" # No need for 'do_make_install', because 'install-static' already has install-instructions.
  cd ..
}

build_fftw() {
  download_and_unpack_file http://fftw.org/fftw-3.3.11.tar.gz
  cd fftw-3.3.11
    generic_configure "--disable-doc"
    do_make_and_make_install
  cd ..
}

build_libsamplerate() {
  # I think this didn't work with ubuntu 14.04 [too old automake or some odd] :|
  do_git_checkout_and_make_install https://github.com/erikd/libsamplerate.git
  # but OS X can't use 0.1.9 :|
  # rubberband can use this, but uses speex bundled by default [any difference? who knows!]
}

build_librubberband() {
  do_git_checkout https://github.com/breakfastquay/rubberband.git rubberband_git "default" # 18c06ab8c431854056407c467f4755f761e36a8e
  activate_meson
  cd rubberband_git
    local meson_options="setup -Dtests=disabled . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    sed -i.bak 's/-lrubberband.*$/-lrubberband -lstdc++/' $PKG_CONFIG_PATH/rubberband.pc
  deactivate
  cd ..
}

build_frei0r() {
  download_and_unpack_file https://github.com/dyne/frei0r/archive/refs/tags/v3.2.1.tar.gz frei0r-3.2.1
  cd frei0r-3.2.1
    sed -i.bak 's/-arch i386//' CMakeLists.txt # OS X https://github.com/dyne/frei0r/issues/64
    do_cmake "-B build -GNinja -DWITHOUT_OPENCV=0 -DWITHOUT_CAIRO=1 -DWITHOUT_GAVL=1 -DCMAKE_C_FLAGS="-mtune=generic"" # cannot handle opencv with lapack+openmp or some cpu specific flags
    do_ninja_and_ninja_install
    mkdir -p $cur_dir/redist # Strip and pack shared libraries.
    if [ $bits_target = 32 ]; then
      local arch=x86
    else
      local arch=x86_64
    fi
    archive="$cur_dir/redist/frei0r-plugins-${arch}-$(git describe --tags).7z"
    if [[ ! -f "$archive.done" ]]; then
      for sharedlib in $x86_64_prefix/lib/frei0r-1/*.dll; do
        ${cross_prefix}strip $sharedlib
      done
      for doc in AUTHORS ChangeLog COPYING README.md; do
        sed "s/$/\r/" $doc > $x86_64_prefix/lib/frei0r-1/$doc.txt
      done
      7z a -mx=9 $archive $x86_64_prefix/lib/frei0r-1 && rm -f $x86_64_prefix/lib/frei0r-1/*.txt
      touch "$archive.done" # for those with no 7z so it won't restrip every time
    fi
  cd ..
}

build_svt-hevc() {
  do_git_checkout https://github.com/OpenVisualCloud/SVT-HEVC.git
  mkdir -p SVT-HEVC_git/release
  cd SVT-HEVC_git/release
    do_cmake_from_build_dir ..
    do_make_and_make_install
  cd ../..
}

build_svt-vp9() {
  do_git_checkout https://github.com/OpenVisualCloud/SVT-VP9.git
  cd SVT-VP9_git/Build
    do_cmake_from_build_dir ..
    do_make_and_make_install
  cd ../..
}

build_svt-av1() {
  do_git_checkout https://github.com/pytorch/cpuinfo.git
  cd cpuinfo_git
    do_cmake_and_install # builds included cpuinfo bugged
  cd ..
  do_git_checkout https://gitlab.com/AOMediaCodec/SVT-AV1.git SVT-AV1_git 
  cd SVT-AV1_git
    do_cmake "-B build -GNinja -DBUILD_TESTING=OFF -DUSE_CPUINFO=SYSTEM -DBUILD_APPS=0" # apps take long time to link
    do_ninja_and_ninja_install
 cd ..
}

build_vidstab() {
  do_git_checkout https://github.com/georgmartius/vid.stab.git vid.stab_git
  cd vid.stab_git
    do_cmake_and_install "-DUSE_OMP=1"
  cd ..
}

build_libmysofa() {
  do_git_checkout https://github.com/hoene/libmysofa.git libmysofa_git "origin/main"
  cd libmysofa_git
    local cmake_params="-DBUILD_TESTS=0"
    if [[ $compiler_flavors == "native" ]]; then
      cmake_params+=" -DCODE_COVERAGE=0"
    fi
    do_cmake "$cmake_params"
    do_make_and_make_install
  cd ..
}

build_libcaca() {
  do_git_checkout https://github.com/cacalabs/libcaca.git libcaca_git # 813baea7a7bc28986e474541dd1080898fac14d7
  cd libcaca_git
    apply_patch file://$patch_dir/libcaca_git_stdio-cruft.diff -p1 # Fix WinXP incompatibility.
    cd caca
      sed -i.bak "s/__declspec(dllexport)//g" *.h # get rid of the declspec lines otherwise the build will fail for undefined symbols
      sed -i.bak "s/__declspec(dllimport)//g" *.h
    cd ..
    generic_configure "--libdir=$x86_64_prefix/lib --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-doc --disable-cocoa --disable-ncurses"
    do_make_and_make_install
    if [[ $compiler_flavors == "native" ]]; then
      sed -i.bak "s/-lcaca.*/-lcaca -lX11/" $PKG_CONFIG_PATH/caca.pc
	 echo "Cflags.private: -DCACA_STATIC" >> $PKG_CONFIG_PATH/caca.pc	
    fi
    echo "Cflags.private: -DCACA_STATIC" >> $PKG_CONFIG_PATH/caca.pc	
  cd ..
}

build_libdecklink() {
  do_git_checkout https://gitlab.com/m-ab-s/decklink-headers.git decklink-headers_git 47d84f8d272ca6872b5440eae57609e36014f3b6
  cd decklink-headers_git
    do_make_install PREFIX=$x86_64_prefix
  cd ..
}

build_zvbi() {
  do_git_checkout https://github.com/zapping-vbi/zvbi.git zvbi_git
  cd zvbi_git
    generic_configure "--disable-dvb --disable-bktr --disable-proxy --disable-nls --without-doxygen --disable-examples --disable-tests --without-libiconv-prefix"							
    do_make_and_make_install
  cd ..
}

build_fribidi() {
  download_and_unpack_file https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz # Get c2man errors building from repo
  cd fribidi-1.0.16
    generic_configure "--disable-debug --disable-deprecated --disable-docs"
    do_make_and_make_install
  cd ..
}

build_libsrt() {
  download_and_unpack_file https://github.com/Haivision/srt/archive/v1.5.5.tar.gz srt-1.5.5
  cd srt-1.5.5
    if [[ $compiler_flavors != "native" ]]; then
      apply_patch file://$patch_dir/srt.app.patch -p1
    fi
    do_cmake "-DUSE_ENCLIB=gnutls -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_CXX_DEPS=ON -DUSE_STATIC_LIBSTDCXX=ON -DENABLE_ENCRYPTION=OFF -DENABLE_APPS=OFF" # latest nettle breaks encryption build...
    do_make_and_make_install
  cd ..
}

build_libass() {
  do_git_checkout_and_make_install https://github.com/libass/libass.git
}

build_vulkan() {
  do_git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers_git v1.4.341
  cd Vulkan-Headers_git
    do_cmake_and_install "-DVULKAN_HEADERS_ENABLE_MODULE=NO -DVULKAN_HEADERS_ENABLE_TESTS=NO -DVULKAN_HEADERS_ENABLE_INSTALL=YES"
  cd ..
}

build_vulkan_loader() {
  do_git_checkout https://github.com/BtbN/Vulkan-Shim-Loader.git Vulkan-Shim-Loader_git 65b3936528cd92eb4ea3de485d03f858a3850484
  cd Vulkan-Shim-Loader_git # credit to btnb for most code for placebo and deps
    # _git_checkout https://github.com/KhronosGroup/Vulkan-Headers.git Vulkan-Headers v1.4.341
    do_cmake_and_install "-DVULKAN_SHIM_IMPERSONATE=ON" # -DVULKAN_HEADERS_ENABLE_MODULE=NO -DVULKAN_HEADERS_ENABLE_TESTS=NO -DVULKAN_HEADERS_ENABLE_INSTALL=YES"
  cd ..
}

build_spirv-cross() {
  do_git_checkout https://github.com/KhronosGroup/SPIRV-Cross.git SPIRV-Cross_git 38681a30e09679191cc3957719eeee76024f6daf
  cd SPIRV-Cross_git
    do_cmake "-B build -GNinja -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_FORCE_PIC=ON -DSPIRV_CROSS_ENABLE_CPP=OFF"
    do_ninja_and_ninja_install
    cat >$PKG_CONFIG_PATH/spirv-cross-c-shared.pc <<EOF
prefix=$x86_64_prefix
exec_prefix=\${prefix}
libdir=\${prefix}/lib
sharedlibdir=\${prefix}/lib
includedir=\${prefix}/include/spirv_cross

Name: spirv-cross-c-shared
Description: C API for SPIRV-Cross
Version: 0.68.0

Requires:
Libs: -L\${libdir} -L\${sharedlibdir} -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-hlsl -lspirv-cross-reflect -lspirv-cross-msl -lspirv-cross-util -lspirv-cross-core -lstdc++
Cflags: -I\${includedir}
EOF
  cd ..
}

build_libdovi() {
  do_git_checkout https://github.com/quietvoid/dovi_tool.git dovi_tool_git
  cd dovi_tool_git
    if [[ ! -e $x86_64_prefix/lib/libdovi.a ]]; then        
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env" && rustup target add x86_64-pc-windows-gnu && rustup update # rustup self uninstall
      unset PKG_CONFIG_PATH	
      cargo install cargo-c --features=vendored-openssl
      export PKG_CONFIG_PATH="$x86_64_prefix/lib/pkgconfig"
      if [[ $compiler_flavors != "native" ]]; then
        cat > $HOME/.cargo/config.toml << EOF
[build]
dep-info-basedir = "sandbox/x86_64/x86_64-w64-mingw32"

[target.x86_64-pc-windows-gnu]
linker = "sandbox/x86_64/bin/x86_64-w64-mingw32-gcc"
ar = "sandbox/x86_64/bin/x86_64-w64-mingw32-ar"
EOF
        ln -s $HOME/sandbox/x86_64//lib/gcc/x86_64-w64-mingw32/15.2.1/libgcc.a $HOME/sandbox/x86_64/x86_64-w64-mingw32/lib/libgcc_eh.a 
        cargo build --release --no-default-features --features internal-font --target x86_64-pc-windows-gnu && cp target/x86_64-pc-windows-gnu/release/dovi_tool.exe $x86_64_prefix/bin
        cd dolby_vision
          cargo cinstall --release --prefix=$x86_64_prefix --libdir=$x86_64_prefix/lib --library-type=staticlib --target x86_64-pc-windows-gnu
        cd ..
      fi
      if [[ $compiler_flavors == "native" ]]; then
        cargo build --release --no-default-features --features internal-font && cp target/release/dovi_tool $x86_64_prefix/bin
        cd dolby_vision
	     cargo cinstall --release --prefix=$x86_64_prefix --libdir=$x86_64_prefix/lib --library-type=staticlib
        cd ..
      fi		
      else echo "libdovi already installed"
    fi
  cd ..
}

build_shaderc() {
  do_git_checkout https://github.com/google/shaderc.git shaderc_git b16fb67935326f7ea1ead8bd2b131608b4148230
  cd shaderc_git
    ./utils/git-sync-deps
     do_cmake "-B build -GNinja -DSHADERC_SKIP_EXAMPLES=1 -DSHADERC_SKIP_TESTS=1 -DSPIRV_SKIP_TESTS=1 -DSHADERC_SKIP_COPYRIGHT_CHECK=1 -DENABLE_EXCEPTIONS=1\
	 -DSPIRV_TOOLS_BUILD_STATIC=1 -DBUILD_SHARED_LIBS=0 -DSPIRV_SKIP_EXECUTABLES=1 -DENABLE_GLSLANG_BINARIES=0" 
	do_ninja_and_ninja_install
     cp build/libshaderc_util/libshaderc_util.a $x86_64_prefix/lib && rm -r $x86_64_prefix/lib/*.dll.a
     sed -i.bak "s/Libs: .*/& -lstdc++/" $PKG_CONFIG_PATH/shaderc_combined.pc
     sed -i.bak "s/Libs: .*/& -lstdc++/" $PKG_CONFIG_PATH/shaderc_static.pc
	sed -i.bak "s/-lshaderc_shared/-lshaderc -lshaderc_combined -lshaderc_util -lstdc++/" $PKG_CONFIG_PATH/shaderc.pc
	unset PKG_CONFIG_PATH
	  cmake -B native_build -GNinja -DCMAKE_BUILD_TYPE=Release -DSHADERC_SKIP_EXAMPLES=1 -DSHADERC_SKIP_TESTS=1 -DSPIRV_SKIP_TESTS=1 -DSHADERC_SKIP_COPYRIGHT_CHECK=1 -DENABLE_EXCEPTIONS=1 -DSPIRV_TOOLS_BUILD_STATIC=1 \
	  -DENABLE_GLSLANG_BINARIES=1 -DSPIRV_SKIP_EXECUTABLES=1 -DBUILD_SHARED_LIBS=0
	 cd native_build && ninja -j$(nproc) glslc/glslc && cp glslc/glslc $x86_64_prefix/bin # && cp glslc/libglslc.a $x86_64_prefix/lib
    export PKG_CONFIG_PATH="$x86_64_prefix/lib/pkgconfig"
  cd ../../
}

build_spriv-headers() {
  do_git_checkout https://github.com/KhronosGroup/SPIRV-Headers.git spriv-headers_git 8c5559c134abcf432ec59db842404087b9906c1a
  cd spriv-headers_git
    do_cmake_and_install "-DSPIRV_HEADERS_ENABLE_TESTS=0 -DSPIRV_HEADERS_ENABLE_INSTALL=1"
  cd ..
}

build_libplacebo() {
  build_vulkan 
  build_vulkan_loader
  do_git_checkout_and_make_install https://github.com/ImageMagick/lcms.git
  build_spirv-cross
  build_libdovi
  build_shaderc
  do_git_checkout https://code.videolan.org/videolan/libplacebo.git libplacebo_git 464d6eab8900c87a539943d0cd8575fffe566f72
  activate_meson
  cd libplacebo_git
    git submodule update --init --recursive --depth=1 --filter=blob:none
	if [[ ! -e subprojects ]]; then
      mkdir subprojects
      meson wrap install xxhash
    fi
    local meson_options="setup --force-fallback-for=xxhash -Ddemos=false -Dvulkan=enabled -Dvk-proc-addr=enabled -Dshaderc=enabled -Dglslang=disabled -Dvulkan-registry=$x86_64_prefix/share/vulkan/registry/vk.xml -Dc_link_args=-static -Dcpp_link_args=-static . build" # https://mesonbuild.com/Dependencies.html#shaderc trigger use of shaderc_combined 
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    sed -i.bak 's/-lplacebo.*$/-lplacebo -lxxhash -lm -lshlwapi -lversion -lstdc++/' $PKG_CONFIG_PATH/libplacebo.pc
  deactivate
  cd ..
}

build_libaribb24() {
  do_git_checkout_and_make_install https://github.com/nkoriyama/aribb24
}

build_libaribcaption() {
  do_git_checkout https://github.com/xqq/libaribcaption
  mkdir libaribcaption/build
  cd libaribcaption/build
    do_cmake_from_build_dir ..
    do_make_and_make_install
  cd ../..
}

build_libxavs() {
  do_git_checkout https://github.com/Distrotech/xavs.git xavs_git
  cd xavs_git
    if [[ ! -f Makefile.bak ]]; then
      sed -i.bak "s/O4/O2/" configure # Change CFLAGS.
    fi
    apply_patch file://$patch_dir/xavs.patch -p1
    do_configure "--host=$host_target --prefix=$x86_64_prefix --cross-prefix=$cross_prefix" # see https://github.com/rdp/ffmpeg-windows-build-helpers/issues/3
    do_make_and_make_install "$make_prefix_options"
    rm -f NUL # cygwin causes windows explorer to not be able to delete this folder if it has this oddly named file in it...
  cd ..
}

build_libxavs2() {
  do_git_checkout https://github.com/pkuvcl/xavs2.git xavs2_git
  cd xavs2_git
  if [ ! -e $PWD/build/linux/already_configured* ]; then
    curl "https://github.com/pkuvcl/xavs2/compare/master...1480c1:xavs2:gcc14/pointerconversion.patch" | git apply -v
  fi
  cd build/linux 
    do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$x86_64_prefix --enable-strip" # --enable-pic
    do_make_and_make_install 
  cd ../../..
}

build_libdavs2() {
  do_git_checkout https://github.com/pkuvcl/davs2.git
  cd davs2_git/build/linux
    if [[ $host_target == 'i686-w64-mingw32' ]]; then
      do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$x86_64_prefix --enable-pic --disable-asm"
    else
      do_configure "--cross-prefix=$cross_prefix --host=$host_target --prefix=$x86_64_prefix --enable-pic"
    fi
    do_make_and_make_install
  cd ../../..
}

build_libxvid() {
  download_and_unpack_file https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz xvidcore
  cd xvidcore/build/generic
    apply_patch file://$patch_dir/xvidcore-1.3.7_static-lib.patch
    do_configure "--host=$host_target --prefix=$x86_64_prefix CFLAGS=-std=gnu17" # no static option...
    do_make_and_make_install
  cd ../../..
}

build_libvpx() {
  do_git_checkout https://chromium.googlesource.com/webm/libvpx.git libvpx_git "origin/main"
  cd libvpx_git
    # apply_patch file://$patch_dir/vpx_160_semaphore.patch -p1 # perhaps someday can remove this after 1.6.0 or mingw fixes it LOL
    if [[ $compiler_flavors == "native" ]]; then
      local config_options=""
    elif [[ "$bits_target" = "32" ]]; then
      local config_options="--target=x86-win32-gcc"
    else
      local config_options="--target=x86_64-win64-gcc"
    fi
    export CROSS="$cross_prefix"  
    # VP8 encoder *requires* sse3 support
    do_configure "$config_options --prefix=$x86_64_prefix --enable-ssse3 --enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth --extra-cflags=-fno-asynchronous-unwind-tables --extra-cflags=-mstackrealign" # fno for Error: invalid register for .seh_savexmm
    do_make_and_make_install
    unset CROSS
  cd ..
}

build_libaom() {
  do_git_checkout https://aomedia.googlesource.com/aom aom_git
  if [[ $compiler_flavors == "native" ]]; then
    local config_options=""
  elif [ "$bits_target" = "32" ]; then
    local config_options="-DCMAKE_TOOLCHAIN_FILE=../cmake/toolchains/x86-mingw-gcc.cmake -DAOM_TARGET_CPU=x86"
  else
    local config_options="-DCMAKE_TOOLCHAIN_FILE=../cmake/toolchains/x86_64-mingw-gcc.cmake -DAOM_TARGET_CPU=x86_64"
  fi
  mkdir -p aom_git/aom_build
  cd aom_git/aom_build
    do_cmake_from_build_dir .. $config_options
    do_make_and_make_install
  cd ../..
}

build_dav1d() {
  do_git_checkout https://code.videolan.org/videolan/dav1d.git libdav1d
  activate_meson
  cd libdav1d
    if [[ $bits_target == 32 || $bits_target == 64 ]]; then # XXX why 64???
      apply_patch file://$patch_dir/david_no_asm.patch -p1 # XXX report
    fi
    cpu_count=1 # XXX report :|
    local meson_options="setup -Denable_tests=false -Denable_examples=false . build"
    if [[ $compiler_flavors != "native" ]]; then
      # get_local_meson_cross_with_propeties 
      meson_options+=" --cross-file=${top_dir}/meson-cross.mingw.txt"
      do_meson "$meson_options"      
    else
      generic_meson "$meson_options"
    fi
    do_ninja_and_ninja_install
    cp build/src/libdav1d.a $x86_64_prefix/lib || exit 1 # avoid 'run ranlib' weird failure, possibly older meson's https://github.com/mesonbuild/meson/issues/4138 :|
    cpu_count=$original_cpu_count
  deactivate
  cd ..
}

build_avisynth() {
  do_git_checkout https://github.com/AviSynth/AviSynthPlus.git avisynth_git
  mkdir -p avisynth_git/avisynth-build
  cd avisynth_git/avisynth-build
    do_cmake_from_build_dir .. -DHEADERS_ONLY:bool=on
    do_make "$make_prefix_options VersionGen install"
  cd ../..
}

build_libvvenc() {
  do_git_checkout https://github.com/fraunhoferhhi/vvenc.git libvvenc_git   
  cd libvvenc_git 
    do_cmake "-B build -DVVENC_ENABLE_LINK_TIME_OPT=OFF -DVVENC_INSTALL_FULLFEATURE_APP=ON -GNinja"
    do_ninja_and_ninja_install
  cd ..
}

build_libvvdec() {
  do_git_checkout https://github.com/fraunhoferhhi/vvdec.git libvvdec_git  
  cd libvvdec_git  
    do_cmake "-B build -DVVDEC_ENABLE_LINK_TIME_OPT=OFF -DVVDEC_INSTALL_VVDECAPP=ON -GNinja"
    do_ninja_and_ninja_install
  cd ..
}

build_libx265() {
  local checkout_dir=x265
  local remote="https://bitbucket.org/multicoreware/x265_git"
  if [[ ! -z $x265_git_checkout_version ]]; then
    checkout_dir+="_$x265_git_checkout_version"
    do_git_checkout "$remote" $checkout_dir "$x265_git_checkout_version"
  else
    if [[ $prefer_stable = "n" ]]; then
      checkout_dir+="_unstable"
      do_git_checkout "$remote" $checkout_dir "origin/master"
    fi
    if [[ $prefer_stable = "y" ]]; then
      do_git_checkout "$remote" $checkout_dir "origin/stable"
    fi
  fi
  cd $checkout_dir

  local cmake_params="-DENABLE_SHARED=0" # build x265.exe

  # Apply x86 noasm detection fix on newer versions
  if [[ $x265_git_checkout_version != *"3.5"* ]] && [[ $x265_git_checkout_version != *"3.4"* ]] && [[ $x265_git_checkout_version != *"3.3"* ]] && [[ $x265_git_checkout_version != *"3.2"* ]] && [[ $x265_git_checkout_version != *"3.1"* ]]; then
    git apply "$patch_dir/x265_x86_noasm_fix.patch"
  fi

  if [ "$bits_target" = "32" ]; then
    cmake_params+=" -DWINXP_SUPPORT=1" # enable windows xp/vista compatibility in x86 build, since it still can I think...
  fi
  mkdir -p 8bit 10bit 12bit

  sed -i.bak '/#include <limits>/{N; s/\n.*$/\n#include <cstdint>/;}' ./source/dynamicHDR10/json11/json11.cpp # needed by gcc 15
  
  # Build 12bit (main12)
  cd 12bit
  local cmake_12bit_params="$cmake_params -DENABLE_CLI=0 -DHIGH_BIT_DEPTH=1 -DENABLE_HDR10_PLUS=1 -DMAIN12=1 -DEXPORT_C_API=0"
  if [ "$bits_target" = "32" ]; then
    cmake_12bit_params="$cmake_12bit_params -DENABLE_ASSEMBLY=OFF" # apparently required or build fails
  fi
  do_cmake_from_build_dir ../source "$cmake_12bit_params"
  do_make
  cp libx265.a ../8bit/libx265_main12.a

  # Build 10bit (main10)
  cd ../10bit
  local cmake_10bit_params="$cmake_params -DENABLE_CLI=0 -DHIGH_BIT_DEPTH=1 -DENABLE_HDR10_PLUS=1 -DEXPORT_C_API=0"
  if [ "$bits_target" = "32" ]; then
    cmake_10bit_params="$cmake_10bit_params -DENABLE_ASSEMBLY=OFF" # apparently required or build fails
  fi
  do_cmake_from_build_dir ../source "$cmake_10bit_params"
  do_make
  cp libx265.a ../8bit/libx265_main10.a

  # Build 8 bit (main) with linked 10 and 12 bit then install
  cd ../8bit
  cmake_params="$cmake_params -DENABLE_CLI=1 -DEXTRA_LINK_FLAGS=-L. -DLINKED_10BIT=1 -DLINKED_12BIT=1"
  if [[ $compiler_flavors == "native" && $OSTYPE != darwin* ]]; then
    cmake_params+=" -DENABLE_SHARED=0 -DEXTRA_LIB='$(pwd)/libx265_main10.a;$(pwd)/libx265_main12.a;-ldl'" # Native multi-lib CLI builds are slightly broken right now; other option is to -DENABLE_CLI=0, but this seems to work (https://bitbucket.org/multicoreware/x265/issues/520)
  else
    cmake_params+=" -DEXTRA_LIB='$(pwd)/libx265_main10.a;$(pwd)/libx265_main12.a'"
  fi
  do_cmake_from_build_dir ../source "$cmake_params"
  do_make
  mv libx265.a libx265_main.a
  if [[ $compiler_flavors == "native" && $OSTYPE == darwin* ]]; then
    libtool -static -o libx265.a libx265_main.a libx265_main10.a libx265_main12.a 2>/dev/null
  else
    ${cross_prefix}ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
  fi
  make install # force reinstall in case you just switched from stable to not :|
  cd ../..
}

build_libopenh264() {
  download_and_unpack_file https://github.com/cisco/openh264/archive/refs/tags/v2.6.0.tar.gz openh264-2.6.0
  cd openh264-2.6.0
    sed -i.bak "s/_M_X64/_M_DISABLED_X64/" codec/encoder/core/inc/param_svc.h # for 64 bit, avoid missing _set_FMA3_enable, it needed to link against msvcrt120 to get this or something weird?
    if [[ $bits_target == 32 ]]; then
      local arch=i686 # or x86?
    else
      local arch=x86_64
    fi
    if [[ $compiler_flavors == "native" ]]; then
      # No need for 'do_make_install', because 'install-static' already has install-instructions. we want install static so no shared built...
      do_make "$make_prefix_options ASM=yasm install-static" # CFLAGS=-std=c18"
    else
      do_make "$make_prefix_options OS=mingw_nt ARCH=$arch ASM=yasm install-static" # CFLAGS=-std=c18"
    fi
  cd ..
}

build_libx264() {
  local checkout_dir="x264"
  if [[ $build_x264_with_libav == "y" ]]; then
    build_ffmpeg static --disable-libx264 ffmpeg_git_pre_x264 # installs libav locally so we can use it within x264.exe FWIW...
    checkout_dir="${checkout_dir}_with_libav"
    # they don't know how to use a normal pkg-config when cross compiling, so specify some manually: (see their mailing list for a request...)
    export LAVF_LIBS="$LAVF_LIBS $(pkg-config --libs libavformat libavcodec libavutil libswscale)"
    export LAVF_CFLAGS="$LAVF_CFLAGS $(pkg-config --cflags libavformat libavcodec libavutil libswscale)"
    export SWSCALE_LIBS="$SWSCALE_LIBS $(pkg-config --libs libswscale)"
  fi

  local x264_profile_guided=n # or y -- haven't gotten this proven yet...TODO

  if [[ $prefer_stable = "n" ]]; then
    checkout_dir="${checkout_dir}_unstable"
    do_git_checkout "https://code.videolan.org/videolan/x264.git" $checkout_dir "origin/master" 
  else
    do_git_checkout "https://code.videolan.org/videolan/x264.git" $checkout_dir  "origin/stable" 
  fi
  cd $checkout_dir
    if [[ ! -f configure.bak ]]; then # Change CFLAGS.
      sed -i.bak "s/O3 -/O2 -/" configure
    fi

    local configure_flags="--host=$host_target --enable-static --cross-prefix=$cross_prefix --prefix=$x86_64_prefix --enable-strip" # --enable-win32thread --enable-debug is another useful option here?
    if [[ $build_x264_with_libav == "n" ]]; then
      configure_flags+=" --disable-lavf" # lavf stands for libavformat, there is no --enable-lavf option, either auto or disable...
    fi
    configure_flags+=" --bit-depth=all"
    for i in $CFLAGS; do
      configure_flags+=" --extra-cflags=$i" # needs it this way seemingly :|
    done

    if [[ $x264_profile_guided = y ]]; then
      # I wasn't able to figure out how/if this gave any speedup...
      # TODO more march=native here?
      # TODO profile guided here option, with wine?
      do_configure "$configure_flags"
      curl -4 http://samples.mplayerhq.hu/yuv4mpeg2/example.y4m.bz2 -O --fail || exit 1
      rm -f example.y4m # in case it exists already...
      bunzip2 example.y4m.bz2 || exit 1
      # XXX does this kill git updates? maybe a more general fix, since vid.stab does also?
      sed -i.bak "s_\\, ./x264_, wine ./x264_" Makefile # in case they have wine auto-run disabled http://askubuntu.com/questions/344088/how-to-ensure-wine-does-not-auto-run-exe-files
      do_make_and_make_install "fprofiled VIDS=example.y4m" # guess it has its own make fprofiled, so we don't need to manually add -fprofile-generate here...
    else
      # normal path non profile guided
      do_configure "$configure_flags"
      do_make
      make install # force reinstall in case changed stable -> unstable
    fi

    unset LAVF_LIBS
    unset LAVF_CFLAGS
    unset SWSCALE_LIBS
  cd ..
}

build_lsmash() { # an MP4 library
  do_git_checkout https://github.com/l-smash/l-smash.git l-smash
  cd l-smash
    do_configure "--prefix=$x86_64_prefix --cross-prefix=$cross_prefix"
    do_make_and_make_install
  cd ..
}

build_libdvdread() {
  build_libdvdcss
  download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdread-4.9.9.tar.xz # last revision before 5.X series so still works with MPlayer
  cd libdvdread-4.9.9
    # XXXX better CFLAGS here...
    generic_configure "CFLAGS=-DHAVE_DVDCSS_DVDCSS_H LDFLAGS=-ldvdcss --enable-dlfcn" # vlc patch: "--enable-libdvdcss" # XXX ask how I'm *supposed* to do this to the dvdread peeps [svn?]
    do_make_and_make_install
    sed -i.bak 's/-ldvdread.*/-ldvdread -ldvdcss/' "$PKG_CONFIG_PATH/dvdread.pc"
  cd ..
}

build_libdvdnav() {
  download_and_unpack_file http://dvdnav.mplayerhq.hu/releases/libdvdnav-4.2.1.tar.xz # 4.2.1. latest revision before 5.x series [?]
  cd libdvdnav-4.2.1
    if [[ ! -f ./configure ]]; then
      ./autogen.sh
    fi
    generic_configure_make_install
    sed -i.bak 's/-ldvdnav.*/-ldvdnav -ldvdread -ldvdcss -lpsapi/' "$PKG_CONFIG_PATH/dvdnav.pc" # psapi for dlfcn ... [hrm?]
  cd ..
}

build_libdvdcss() {
  generic_download_and_make_and_install https://download.videolan.org/pub/videolan/libdvdcss/1.2.13/libdvdcss-1.2.13.tar.bz2
}

build_libproxy() {
  # NB this lacks a .pc file still
  download_and_unpack_file https://libproxy.googlecode.com/files/libproxy-0.4.11.tar.gz
  cd libproxy-0.4.11
    sed -i.bak "s/= recv/= (void *) recv/" libmodman/test/main.cpp # some compile failure
    do_cmake_and_install
  cd ..
}

build_lua() {
  download_and_unpack_file https://www.lua.org/ftp/lua-5.3.3.tar.gz
  cd lua-5.3.3
    export AR="${cross_prefix}ar rcu" # needs rcu parameter so have to call it out different :|
    do_make "CC=${cross_prefix}gcc RANLIB=${cross_prefix}ranlib generic" # generic == "generic target" and seems to result in a static build, no .exe's blah blah the mingw option doesn't even build liblua.a
    unset AR
    do_make_install "INSTALL_TOP=$x86_64_prefix" "generic install"
    cp etc/lua.pc $PKG_CONFIG_PATH
  cd ..
}

build_libhdhomerun() {
  exit 1 # still broken unfortunately, for cross compile :|
  download_and_unpack_file https://download.silicondust.com/hdhomerun/libhdhomerun_20150826.tgz libhdhomerun
  cd libhdhomerun
    do_make CROSS_COMPILE=$cross_prefix  OS=Windows_NT
  cd ..
}

build_dvbtee_app() {
  build_iconv # said it needed it
  build_curl # it "can use this" so why not
  #  build_libhdhomerun # broken but possible dependency apparently :|
  do_git_checkout https://github.com/mkrufky/libdvbtee.git libdvbtee_git
  cd libdvbtee_git
    # checkout its submodule, apparently required
    if [ ! -e libdvbpsi/bootstrap ]; then
      rm -rf libdvbpsi # remove placeholder
      do_git_checkout https://github.com/mkrufky/libdvbpsi.git
      cd libdvbpsi_git
        generic_configure_make_install # library dependency submodule... TODO don't install it, just leave it local :)
      cd ..
    fi
    generic_configure
    do_make # not install since don't have a dependency on the library
  cd ..
}

build_qt() {
   # libjpeg a dependency [?]
  unset CFLAGS # it makes something of its own first, which runs locally, so can't use a foreign arch, or maybe it can, but not important enough: http://stackoverflow.com/a/18775859/32453 XXXX could look at this
  #download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.7.tar.gz/d990ee66bf7ab0c785589776f35ba6ad/qt-everywhere-opensource-src-4.8.7.tar.gz # untested
  #cd qt-everywhere-opensource-src-4.8.7
  # download_and_unpack_file http://download.qt-project.org/official_releases/qt/5.1/5.1.1/submodules/qtbase-opensource-src-5.1.1.tar.xz qtbase-opensource-src-5.1.1 # not officially supported seems...so didn't try it
  download_and_unpack_file http://pkgs.fedoraproject.org/repo/pkgs/qt/qt-everywhere-opensource-src-4.8.5.tar.gz/1864987bdbb2f58f8ae8b350dfdbe133/qt-everywhere-opensource-src-4.8.5.tar.gz
  cd qt-everywhere-opensource-src-4.8.5
    apply_patch file://$patch_dir/imageformats.patch
    apply_patch file://$patch_dir/qt-win64.patch
    # vlc's configure options...mostly
    do_configure "-static -release -fast -no-exceptions -no-stl -no-sql-sqlite -no-qt3support -no-gif -no-libmng -qt-libjpeg -no-libtiff -no-qdbus -no-openssl -no-webkit -sse -no-script -no-multimedia -no-phonon -opensource -no-scripttools -no-opengl -no-script -no-scripttools -no-declarative -no-declarative-debug -opensource -no-s60 -host-little-endian -confirm-license -xplatform win32-g++ -device-option CROSS_COMPILE=$cross_prefix -prefix $x86_64_prefix -prefix-install -nomake examples"
    if [ ! -f 'already_qt_maked_k' ]; then
      make sub-src -j $cpu_count
      make install sub-src # let it fail, baby, it still installs a lot of good stuff before dying on mng...? huh wuh?
      cp ./plugins/imageformats/libqjpeg.a $x86_64_prefix/lib || exit 1 # I think vlc's install is just broken to need this [?]
      cp ./plugins/accessible/libqtaccessiblewidgets.a  $x86_64_prefix/lib || exit 1 # this feels wrong...
      # do_make_and_make_install "sub-src" # sub-src might make the build faster? # complains on mng? huh?
      touch 'already_qt_maked_k'
    fi
    # vlc needs an adjust .pc file? huh wuh?
    sed -i.bak 's/Libs: -L${libdir} -lQtGui/Libs: -L${libdir} -lcomctl32 -lqjpeg -lqtaccessiblewidgets -lQtGui/' "$PKG_CONFIG_PATH/QtGui.pc" # sniff
  cd ..
  reset_cflags
}

build_vlc() {
  # currently broken, since it got too old for libavcodec and I didn't want to build its own custom one yet to match, and now it's broken with gcc 5.2.0 seemingly
  # call out dependencies here since it's a lot, plus hierarchical FTW!
  # should be ffmpeg 1.1.1 or some odd?
  echo "not building vlc, broken dependencies or something weird"
  return
  # vlc's own dependencies:
  build_lua
  build_libdvdread
  build_libdvdnav
  build_libx265
  
  build_ffmpeg
  build_qt

  # currently vlc itself currently broken :|
  do_git_checkout https://github.com/videolan/vlc.git
  cd vlc_git
  #apply_patch file://$patch_dir/vlc_localtime_s.patch # git revision needs it...
  # outdated and patch doesn't apply cleanly anymore apparently...
  #if [[ "$non_free" = "y" ]]; then
  #  apply_patch https://raw.githubusercontent.com/gcsx/ffmpeg-windows-build-helpers/patch-5/patches/priorize_avcodec.patch
  #fi
  if [[ ! -f "configure" ]]; then
    ./bootstrap
  fi
  export DVDREAD_LIBS='-ldvdread -ldvdcss -lpsapi'
  do_configure "--disable-libgcrypt --disable-a52 --host=$host_target --disable-lua --disable-mad --enable-qt --disable-sdl --disable-mod" # don't have lua mingw yet, etc. [vlc has --disable-sdl [?]] x265 disabled until we care enough... Looks like the bluray problem was related to the BLURAY_LIBS definition. [not sure what's wrong with libmod]
  rm -f `find . -name *.exe` # try to force a rebuild...though there are tons of .a files we aren't rebuilding as well FWIW...:|
  rm -f already_ran_make* # try to force re-link just in case...
  do_make
  # do some gymnastics to avoid building the mozilla plugin for now [couldn't quite get it to work]
  #sed -i.bak 's_git://git.videolan.org/npapi-vlc.git_https://github.com/rdp/npapi-vlc.git_' Makefile # this wasn't enough...following lines instead...
  sed -i.bak "s/package-win-common: package-win-install build-npapi/package-win-common: package-win-install/" Makefile
  sed -i.bak "s/.*cp .*builddir.*npapi-vlc.*//g" Makefile
  make package-win-common # not do_make, fails still at end, plus this way we get new vlc.exe's
  echo "


     vlc success, created a file like ${PWD}/vlc-xxx-git/vlc.exe



"
  cd ..
  unset DVDREAD_LIBS
}

reset_cflags() {
  export CFLAGS=$original_cflags
}

reset_cppflags() {
  export CPPFLAGS=$original_cppflags
}

reset_cxxflags() {
  export CXXFLAGS=$original_cxxflags
}

build_meson_cross() {
  local cpu_family="x86_64"
  if [ $bits_target = 32 ]; then
    cpu_family="x86"
  fi
  rm -fv meson-cross.mingw.txt
  cat >> meson-cross.mingw.txt << EOF
[built-in options]
buildtype = 'release'
wrap_mode = 'nofallback'  
default_library = 'static'  
prefer_static = 'true'
default_both_libraries = 'static'
backend = 'ninja'
prefix = '$x86_64_prefix'
libdir = '$x86_64_prefix/lib'
 
[binaries]
c = '${cross_prefix}gcc'
cpp = '${cross_prefix}g++'
ld = '${cross_prefix}ld'
ar = '${cross_prefix}ar'
strip = '${cross_prefix}strip'
nm = '${cross_prefix}nm'
fc = '${cross_prefix}gfortran'
cuda = 'nvcc'
windres = '${cross_prefix}windres'
dlltool = '${cross_prefix}dlltool'
pkg-config = 'pkg-config'
nasm = 'nasm'
cmake = 'cmake'

[host_machine]
system = 'windows'
cpu_family = '$cpu_family'
cpu = '$cpu_family'
endian = 'little'

[properties]
pkg_config_sysroot_dir = '$x86_64_prefix'
pkg_config_libdir = '$pkg_config_sysroot_dir/lib/pkgconfig'
EOF
  mv -v meson-cross.mingw.txt ../..
}

get_local_meson_cross_with_propeties() {
  local local_dir="$1"
  if [[ -z $local_dir ]]; then
    local_dir="."
  fi
  cp ${top_dir}/meson-cross.mingw.txt "$local_dir"
  cat >> meson-cross.mingw.txt << EOF
EOF
}

build_mplayer() {
  # pre requisites
  
  build_libdvdread
  build_libdvdnav

  download_and_unpack_file https://sourceforge.net/projects/mplayer-edl/files/mplayer-export-snapshot.2014-05-19.tar.bz2 mplayer-export-2014-05-19
  cd mplayer-export-2014-05-19
    do_git_checkout https://github.com/FFmpeg/FFmpeg ffmpeg d43c303038e9bd # known compatible commit
    export LDFLAGS='-pthread -ldvdnav -ldvdread -ldvdcss' # not compat with newer dvdread possibly? huh wuh?
    export CFLAGS=-DHAVE_DVDCSS_DVDCSS_H
    do_configure "--enable-cross-compile --host-cc=cc --cc=${cross_prefix}gcc --windres=${cross_prefix}windres --ranlib=${cross_prefix}ranlib --ar=${cross_prefix}ar --as=${cross_prefix}as --nm=${cross_prefix}nm --enable-runtime-cpudetection --extra-cflags=$CFLAGS --with-dvdnav-config=$x86_64_prefix/bin/dvdnav-config --disable-dvdread-internal --disable-libdvdcss-internal --disable-w32threads --enable-pthreads --extra-libs=-lpthread --enable-debug --enable-ass-internal --enable-dvdread --enable-dvdnav --disable-libvpx-lavc" # haven't reported the ldvdcss thing, think it's to do with possibly it not using dvdread.pc [?] XXX check with trunk
    # disable libvpx didn't work with its v1.5.0 some reason :|
    unset LDFLAGS
    reset_cflags
    sed -i.bak "s/HAVE_PTHREAD_CANCEL 0/HAVE_PTHREAD_CANCEL 1/g" config.h # mplayer doesn't set this up right?
    touch -t 201203101513 config.h # the above line change the modify time for config.h--forcing a full rebuild *every time* yikes!
    # try to force re-link just in case...
    rm -f *.exe
    rm -f already_ran_make* # try to force re-link just in case...
    do_make
    cp mplayer.exe mplayer_debug.exe
    ${cross_prefix}strip mplayer.exe
    echo "built ${PWD}/{mplayer,mencoder,mplayer_debug}.exe"
  cd ..
}

build_mp4box() { # like build_gpac
  # This script only builds the gpac_static lib plus MP4Box. Other tools inside
  # specify revision until this works: https://sourceforge.net/p/gpac/discussion/287546/thread/72cf332a/
  do_git_checkout https://github.com/gpac/gpac.git mp4box_gpac_git
  cd mp4box_gpac_git
    # are these tweaks needed? If so then complain to the mp4box people about it?
    sed -i.bak "s/has_dvb4linux=\"yes\"/has_dvb4linux=\"no\"/g" configure
    # XXX do I want to disable more things here?
    # ./sandbox/mingw-w64-i686/bin/i686-w64-mingw32-sdl-config
    generic_configure "  --cross-prefix=${cross_prefix} --target-os=MINGW32 --extra-cflags=-Wno-format --static-build --static-bin --disable-oss-audio --extra-ldflags=-municode --disable-x11 --sdl-cfg=${cross_prefix}sdl-config"
    ./check_revision.sh
    # I seem unable to pass 3 libs into the same config line so do it with sed...
    sed -i.bak "s/EXTRALIBS=.*/EXTRALIBS=-lws2_32 -lwinmm -lz/g" config.mak
    cd src
      do_make "$make_prefix_options"
    cd ..
    rm -f ./bin/gcc/MP4Box* # try and force a relink/rebuild of the .exe
    cd applications/mp4box
      rm -f already_ran_make* # ??
      do_make "$make_prefix_options"
    cd ../..
    # copy it every time just in case it was rebuilt...
    cp ./bin/gcc/MP4Box ./bin/gcc/MP4Box.exe # it doesn't name it .exe? That feels broken somehow...
    echo "built $(readlink -f ./bin/gcc/MP4Box.exe)"
  cd ..
}

build_libMXF() {
  download_and_unpack_file https://sourceforge.net/projects/ingex/files/1.0.0/libMXF/libMXF-src-1.0.0.tgz "libMXF-src-1.0.0"
  cd libMXF-src-1.0.0
    apply_patch file://$patch_dir/libMXF.diff
    do_make "MINGW_CC_PREFIX=$cross_prefix"
    #
    # Manual equivalent of make install. Enable it if desired. We shouldn't need it in theory since we never use libMXF.a file and can just hand pluck out the *.exe files already...
    #
    #cp libMXF/lib/libMXF.a $x86_64_prefix/lib/libMXF.a
    #cp libMXF++/libMXF++/libMXF++.a $x86_64_prefix/lib/libMXF++.a
    #mv libMXF/examples/writeaviddv50/writeaviddv50 libMXF/examples/writeaviddv50/writeaviddv50.exe
    #mv libMXF/examples/writeavidmxf/writeavidmxf libMXF/examples/writeavidmxf/writeavidmxf.exe
    #cp libMXF/examples/writeaviddv50/writeaviddv50.exe $x86_64_prefix/bin/writeaviddv50.exe
    #cp libMXF/examples/writeavidmxf/writeavidmxf.exe $x86_64_prefix/bin/writeavidmxf.exe
  cd ..
}

build_ffmpeg() {
  local extra_postpend_configure_options=$2
  local build_type=$1
  if [[ -z $3 ]]; then
    local output_dir="ffmpeg_git"
  else
    local output_dir=$3
  fi
  if [[ "$non_free" = "y" ]]; then
    output_dir+="_with_fdk_aac"
  fi
  if [[ $build_intel_qsv == "n" ]]; then
    output_dir+="_xp_compat"
  fi
  if [[ $enable_gpl == 'n' ]]; then
    output_dir+="_lgpl"
  fi

  if [[ ! -z $ffmpeg_git_checkout_version ]]; then
    local output_branch_sanitized=$(echo ${ffmpeg_git_checkout_version} | sed "s/\//_/g") # release/4.3 to release_4.3
    output_dir+="_$output_branch_sanitized"
  else
    # If version not provided, assume master branch desired
    ffmpeg_git_checkout_version="master"
  fi

  local postpend_configure_opts=""
  local install_prefix=""
  # can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
  if [[ $build_type == "shared" ]]; then
    output_dir+="_shared"
    install_prefix="$(pwd)/${output_dir}" # install them to their a separate dir
  else
    install_prefix="${x86_64_prefix}" # don't really care since we just pluck ffmpeg.exe out of the src dir for static, but x264 pre wants it installed...
  fi

  # allow using local source directory version of ffmpeg
  if [[ -z $ffmpeg_source_dir ]]; then
    do_git_checkout $ffmpeg_git_checkout $output_dir $ffmpeg_git_checkout_version || exit 1
  else
    output_dir="${ffmpeg_source_dir}"
    install_prefix="${output_dir}"
  fi

  if [[ $build_type == "shared" ]]; then
    postpend_configure_opts="--enable-shared --disable-static --prefix=${install_prefix}" # I guess this doesn't have to be at the end...
  else
    postpend_configure_opts="--enable-static --disable-shared --prefix=${install_prefix}"
  fi

  if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
    postpend_configure_opts="${postpend_configure_opts} --disable-libdav1d " # dav1d has diverged since so isn't compat with older ffmpegs
  fi

  cd $output_dir
    apply_patch file://$patch_dir/frei0r_load-shared-libraries-dynamically.diff
    if [ "$bits_target" = "32" ]; then
      local arch=x86
    else
      local arch=amd64
    fi

    init_options="--pkg-config=pkg-config --pkg-config-flags=--static --enable-version3 --disable-w32threads" # --disable-debug
    if [[ $compiler_flavors != "native" ]]; then
      init_options+=" --arch=$arch --target-os=mingw64 --cross-prefix=$cross_prefix"
    else
      if [[ $OSTYPE != darwin* ]]; then
        unset PKG_CONFIG_LIBDIR # just use locally packages for all the xcb stuff for now, you need to install them locally first...
        init_options+=" --enable-libv4l2 --enable-libxcb --enable-libxcb-shm --enable-libxcb-xfixes --enable-libxcb-shape "
      fi
    fi
    if [[ `uname` =~ "5.1" ]]; then
      init_options+=" --disable-schannel"
      # Fix WinXP incompatibility by disabling Microsoft's Secure Channel, because Windows XP doesn't support TLS 1.1 and 1.2, but with GnuTLS or OpenSSL it does.  XP compat!
    fi    
    config_options="$init_options"
    # alphabetized :)
    config_options+=" --enable-bzlib"	
    config_options+=" --enable-cuda"
    config_options+=" --enable-cuda-llvm"
    config_options+=" --enable-cuda-nvcc"
    config_options+=" --enable-cuvid"
    config_options+=" --enable-ffnvcodec" 
    config_options+=" --enable-fontconfig"
    config_options+=" --enable-gmp"
    config_options+=" --enable-gnutls"	
    config_options+=" --enable-gray"
    config_options+=" --enable-iconv"
    config_options+=" --enable-lcms2"		
    config_options+=" --enable-libass"	
    config_options+=" --enable-libbluray"
    config_options+=" --enable-libbs2b"
    config_options+=" --enable-libcaca"
    config_options+=" --enable-libdav1d"
    config_options+=" --enable-libflite"
    config_options+=" --enable-libfreetype"
    config_options+=" --enable-libfribidi"
    # config_options+=" --enable-libglslang" # this or libshaderc not both
    config_options+=" --enable-libgme"
    config_options+=" --enable-libgsm"	
    config_options+=" --enable-libharfbuzz"
    config_options+=" --enable-filter=drawtext"
    config_options+=" --enable-libilbc"
    config_options+=" --enable-liblensfun"
    config_options+=" --enable-libmodplug"
    config_options+=" --enable-libmp3lame" && sed -i 's|require "libmp3lame >= 3.98.3" lame/lame.h|require_pkg_config libmp3lame lame lame/lame.h|' configure
    config_options+=" --enable-libmysofa"
    config_options+=" --enable-libopencore-amrnb"
    config_options+=" --enable-libopencore-amrwb"
    config_options+=" --enable-libopencv"
    config_options+=" --enable-libopenh264"  
    config_options+=" --enable-libopenjpeg"
    config_options+=" --enable-libopenmpt"
    # config_options+=" --enable-libopenssl"
    config_options+=" --enable-libopus"
    if [[ $OSTYPE != darwin* ]]; then
      config_options+=" --enable-libplacebo"
    fi
    config_options+=" --enable-libshaderc" 	
    config_options+=" --enable-libsnappy"
    config_options+=" --enable-libsoxr" && sed -i 's|require libsoxr soxr.h|require_pkg_config libsoxr libsoxr soxr.h|' configure
    config_options+=" --enable-libspeex"
    config_options+=" --enable-libsrt"
    # config_options+=" --enable-libtensorflow"
    config_options+=" --enable-libtesseract"
    config_options+=" --enable-libtheora"
    config_options+=" --enable-libtwolame" && sed -i 's|require libtwolame twolame.h|require_pkg_config libtwolame libtwolame twolame.h|' configure 
    config_options+=" --enable-libvmaf"
    config_options+=" --enable-libvo-amrwbenc"
    config_options+=" --enable-libvorbis"
    config_options+=" --enable-libvvdec" && apply_patch "https://raw.githubusercontent.com/wiki/fraunhoferhhi/vvdec/data/patch/v7-0001-avcodec-add-external-dec-libvvdec-for-H266-VVC.patch" -p1
    config_options+=" --enable-libvvenc"
    config_options+=" --enable-libwebp"
    config_options+=" --enable-libxml2"
    config_options+=" --enable-libzvbi"   
    config_options+=" --enable-libzimg"
    config_options+=" --enable-lzma" 
    config_options+=" --enable-mediafoundation"	
    config_options+=" --enable-opencl"
    config_options+=" --enable-opengl"
    config_options+=" --enable-sdl2"
    if [[ $OSTYPE != darwin* ]]; then
      config_options+=" --enable-vulkan"
    fi
    # config_options+=" --enable-whisper"
    config_options+=" --enable-zlib"
    if [[ "$bits_target" != "32" ]]; then
      if [[ $build_svt_hevc = y ]]; then
        # SVT-HEVC
        # Apply the correct patches based on version. Logic (n4.4 patch for n4.2, n4.3 and n4.4)  based on patch notes here:
        # https://github.com/OpenVisualCloud/SVT-HEVC/commit/b5587b09f44bcae70676f14d3bc482e27f07b773#diff-2b35e92117ba43f8397c2036658784ba2059df128c9b8a2625d42bc527dffea1
        if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
          git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/n4.4-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
          git apply "$patch_dir/SVT-HEVC-0002-doc-Add-libsvt_hevc-encoder-docs.patch"  # upstream patch does not apply on current ffmpeg master
	elif [[ $ffmpeg_git_checkout_version == *"n4.1"* ]] || [[ $ffmpeg_git_checkout_version == *"n3"* ]] || [[ $ffmpeg_git_checkout_version == *"n2"* ]]; then
          : # too old...
        else
          # newer:
          git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/master-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
        fi
        config_options+=" --enable-libsvthevc"
      fi
      if [[ $build_svt_vp9 = y ]]; then
        # SVT-VP9
        # Apply the correct patches based on version. Logic (n4.4 patch for n4.2, n4.3 and n4.4)  based on patch notes here:
        # https://github.com/OpenVisualCloud/SVT-VP9/tree/master/ffmpeg_plugin
        if [[ $ffmpeg_git_checkout_version == *"n4.3.1"* ]]; then
          git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.3.1-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
        elif [[ $ffmpeg_git_checkout_version == *"n4.2.3"* ]]; then
          git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/n4.2.3-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
        elif [[ $ffmpeg_git_checkout_version == *"n4.2.2"* ]]; then
          git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
        else 
          # newer:
          git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"
        fi
        config_options+=" --enable-libsvtvp9"
      fi

      config_options+=" --enable-libsvtav1"
    fi # else doesn't work/matter with 32 bit
    config_options+=" --enable-libvpx"
    config_options+=" --enable-libaom"

    if [[ $compiler_flavors != "native" ]]; then
      config_options+=" --enable-nvenc --enable-nvdec" # don't work OS X
    fi
    # the order of extra-libs switches is important (appended in reverse)
    # config_options+=" --extra-libs=-lz"
    # config_options+=" --extra-libs=-lpng"
    # config_options+=" --extra-libs=-lm" # libflite seemed to need this linux native...and have no .pc file huh?
    # config_options+=" --extra-libs=-lfreetype"

    # if [[ $compiler_flavors != "native" ]]; then
      # config_options+=" --extra-libs=-lshlwapi" # lame needed this, no .pc file?
    # fi
    # config_options+=" --extra-libs=-lmpg123" # ditto
    config_options+=" --extra-libs=-pthread" # for some reason various and sundry needed this linux native

    # config_options+=" --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC --extra-cflags=-DCACA_STATIC"

    if [[ $build_amd_amf = n ]]; then
      config_options+=" --disable-amf" # Since its autodetected we have to disable it if we do not want it. #unless we define no autodetection but.. we don't.
    else
      config_options+=" --enable-amf" # This is actually autodetected but for consistency.. we might as well set it.
    fi

    if [[ $build_intel_qsv = y && $compiler_flavors != "native" ]]; then 
      config_options+=" --enable-libvpl"
    else
      config_options+=" --disable-libvpl"
    fi
    
	if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then
      # Disable libaribcatption on old versions
      config_options+=" --enable-libaribcaption" # libaribcatption (MIT licensed)
    fi
    
    if [[ $enable_gpl == 'y' ]]; then
      config_options+=" --enable-gpl --enable-frei0r --enable-librubberband --enable-libvidstab --enable-libx264 --enable-libx265 --enable-avisynth --enable-libaribb24"
      config_options+=" --enable-libxvid --enable-libdavs2"
      if [[ $host_target != 'i686-w64-mingw32' ]]; then
        config_options+=" --enable-libxavs2"
      fi
      if [[ $compiler_flavors != "native" ]]; then
        config_options+=" --enable-libxavs" # don't compile OS X
      fi
    fi
    local licensed_gpl=n # lgpl build with libx264 included for those with "commercial" license :)
    if [[ $licensed_gpl == 'y' ]]; then
      apply_patch file://$patch_dir/x264_non_gpl.diff -p1
      config_options+=" --enable-libx264"
    fi

    # for i in $CFLAGS; do
      # config_options+=" --extra-cflags=$i" # --extra-cflags may not be needed here, but adds it to the final console output which I like for debugging purposes
    # done

    config_options+=" $postpend_configure_opts"

    if [[ "$non_free" = "y" ]]; then
      config_options+=" --enable-nonfree --enable-libfdk-aac"
      if [[ $OSTYPE != darwin* ]]; then
        config_options+=" --enable-audiotoolbox --extra-libs=-lAudioToolboxWrapper" && sed -i 's/check_apple_framework AudioToolbox.*/check_apple_framework CoreAudio/' configure
      fi
      if [[ $compiler_flavors != "native" ]]; then
        config_options+=" --enable-decklink" # Error finding rpc.h in native builds even if it's available
      fi
      # other possible options: --enable-openssl [unneeded since we already use gnutls]
    fi

    do_debug_build=n # if you need one for backtraces/examining segfaults using gdb.exe ... change this to y :) XXXX make it affect x264 too...and make it real param :)
    if [[ "$do_debug_build" = "y" ]]; then
      # not sure how many of these are actually needed/useful...possibly none LOL
      config_options+=" --disable-optimizations --extra-cflags=-Og --extra-cflags=-fno-omit-frame-pointer --enable-debug=3 --extra-cflags=-fno-inline $postpend_configure_opts"
      # this one kills gdb workability for static build? ai ai [?] XXXX
      config_options+=" --disable-libgme"
    fi
    config_options+=" $extra_postpend_configure_options"

    do_configure "$config_options"
    rm -f */*.a */*.dll *.exe # just in case some dependency library has changed, force it to re-link even if the ffmpeg source hasn't changed...
    rm -f already_ran_make*
    echo "doing ffmpeg make $(pwd)"

    do_make_and_make_install # install ffmpeg as well (for shared, to separate out the .dll's, for things that depend on it like VLC, to create static libs)

    # build ismindex.exe, too, just for fun
    if [[ $build_ismindex == "y" ]]; then
      make tools/ismindex.exe || exit 1
    fi

    # # XXX really ffmpeg should have set this up right but doesn't, patch FFmpeg itself instead...
    if [[ $1 == "static" ]]; then
     # nb we can just modify this every time, it getes recreated, above..
      if [[ $compiler_flavors != "native" ]]; then # Broken for native builds right now: https://github.com/lu-zero/mfx_dispatch/issues/71
        sed -i.bak 's/-ldl/-ldl -lmpg123 -lshlwapi /' "$PKG_CONFIG_PATH/libavutil.pc"
      fi
    fi

    if [[ $non_free == "y" ]]; then
      if [[ $build_type == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)/bin"
      else
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)"
      fi
    else
      mkdir -p $cur_dir/redist
      archive="$cur_dir/redist/ffmpeg-$(git describe --tags --match N)-win$bits_target-$1"
      if [[ $original_cflags =~ "pentium3" ]]; then
        archive+="_legacy"
      fi
      if [[ $build_type == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)/bin"
        # Some manual package stuff because the install_root may be cluttered with static as well...
        # XXX this misses the docs and share?
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > bin/COPYING.GPLv3.txt # XXX we include this even if it's not a GPL build?
          cp -r include bin
          cd bin
            7z a -mx=9 $archive.7z include *.exe *.dll *.lib COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
          cd ..
        fi
      else
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)" `date`
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > COPYING.GPLv3.txt
          echo "creating distro zip..." # XXX opt in?
          7z a -mx=9 $archive.7z ffmpeg.exe ffplay.exe ffprobe.exe COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
        else
          echo "not creating distro zip as one already exists..."
        fi
      fi
      echo "You will find redistributable archive .7z file in $archive.7z"
    fi

  if [[ -z $ffmpeg_source_dir ]]; then
    cd ..
  else
    cd "$work_dir"
  fi
}

build_lsw() {
   # Build L-Smash-Works, which are AviSynth plugins based on lsmash/ffmpeg
   #build_ffmpeg static # dependency, assume already built since it builds before this does...
   build_lsmash # dependency
   do_git_checkout https://github.com/VFR-maniac/L-SMASH-Works.git lsw
   cd lsw/VapourSynth
     do_configure "--prefix=$x86_64_prefix --cross-prefix=$cross_prefix --target-os=mingw"
     do_make_and_make_install
     # AviUtl is 32bit-only
     if [ "$bits_target" = "32" ]; then
       cd ../AviUtl
       do_configure "--prefix=$x86_64_prefix --cross-prefix=$cross_prefix"
       do_make
     fi
   cd ../..
}

find_all_build_exes() {
  local found=""
# NB that we're currently in the sandbox dir...
  for file in `find . -name ffmpeg.exe` `find . -name ffmpeg_g.exe` `find . -name ffplay.exe` `find . -name ffmpeg` `find . -name ffplay` `find . -name ffprobe` `find . -name MP4Box.exe` `find . -name mplayer.exe` `find . -name mencoder.exe` `find . -name avconv.exe` `find . -name avprobe.exe` `find . -name x264.exe` `find . -name writeavidmxf.exe` `find . -name writeaviddv50.exe` `find . -name rtmpdump.exe` `find . -name x265.exe` `find . -name ismindex.exe` `find . -name dvbtee.exe` `find . -name boxdumper.exe` `find . -name muxer.exe ` `find . -name remuxer.exe` `find . -name timelineeditor.exe` `find . -name lwcolor.auc` `find . -name lwdumper.auf` `find . -name lwinput.aui` `find . -name lwmuxer.auf` `find . -name vslsmashsource.dll`; do
    found="$found $(readlink -f $file)"
  done

  # bash recursive glob fails here again?
  for file in `find . -name vlc.exe | grep -- -`; do
    found="$found $(readlink -f $file)"
  done
  echo $found # pseudo return value...
}

build_ffmpeg_dependencies() {
  if [[ $build_dependencies = "n" ]]; then
    echo "Skip build ffmpeg dependency libraries..."
    return
  fi

  echo "Building ffmpeg dependency libraries..."
  if [[ $compiler_flavors != "native" ]]; then # build some stuff that don't build native...
    build_dlfcn
    build_libxavs
  fi
  build_libdavs2
  if [[ $host_target != 'i686-w64-mingw32' ]]; then
    build_libxavs2
  fi
  build_meson_cross
  build_mingw_std_threads
  build_zlib # Zlib in FFmpeg is autodetected.
  build_libcaca # Uses zlib and dlfcn (on windows).
  build_bzip2 # Bzlib (bzip2) in FFmpeg is autodetected.
  build_liblzma # Lzma in FFmpeg is autodetected. Uses dlfcn.
  build_iconv # Iconv in FFmpeg is autodetected. Uses dlfcn.
  build_sdl2 # Sdl2 in FFmpeg is autodetected. Needed to build FFPlay. Uses iconv and dlfcn.
  if [[ $build_amd_amf = y ]]; then
    build_amd_amf_headers
  fi
  if [[ $build_intel_qsv = y && $compiler_flavors != "native" ]]; then
    build_libvpl
  fi
  build_nv_headers
  install_cudatoolkit # v13.3
  build_libzimg # Uses dlfcn.
  build_libopenjpeg
  build_glew
  build_glfw
  build_libjpeg_turbo
  build_libpng # Needs zlib >= 1.0.4. Uses dlfcn.
  build_libwebp # Uses dlfcn.
  build_libxml2 # Uses zlib, liblzma, iconv and dlfcn
  build_brotli
  build_harfbuzz # Uses freetype zlib, bzip2, brotli and libpng.
  build_libvmaf
  build_fontconfig # uses libpng bzip2 libxml2 and zlib
  build_gmp # c18
  build_libnettle # Needs gmp >= 3.0. Uses dlfcn. c18
  build_unistring
  build_libidn2 # needs iconv and unistring
  build_zstd
  build_gnutls # Needs nettle >= 3.1, hogweed (nettle) >= 3.1. Uses libidn2, unistring, zlib, and dlfcn.
  build_openssl-3.0.8
  build_curl
  build_libogg # Uses dlfcn.
  build_libvorbis # Needs libogg >= 1.0. Uses dlfcn.
  build_libopus # Uses dlfcn.
  build_libspeexdsp # Needs libogg for examples. Uses dlfcn.
  build_libspeex # Uses libspeexdsp and dlfcn.
  build_libtheora # Needs libogg >= 1.1. Needs libvorbis >= 1.0.1, sdl and libpng for test, programs and examples [disabled]. Uses dlfcn.
  build_libsndfile "install-libgsm" # Needs libogg >= 1.1.3 and libvorbis >= 1.2.3 for external support [disabled]. Uses dlfcn. 'build_libsndfile "install-libgsm"' to install the included LibGSM 6.10.
  build_mpg123
  build_lame # Uses dlfcn, mpg123
  build_twolame # Uses libsndfile >= 1.0.0 and dlfcn.
  build_openmpt
  build_libopencore # Uses dlfcn.
  build_libilbc # Uses dlfcn.
  build_libmodplug # Uses dlfcn.
  build_libgme
  build_libbluray # Needs libxml >= 2.6, freetype, fontconfig. Uses dlfcn.
  build_libbs2b # Needs libsndfile. Uses dlfcn.
  build_libsoxr
  build_libflite
  build_libsnappy # Uses zlib (only for unittests [disabled]) and dlfcn.
  # build_vamp_plugin # Needs libsndfile for 'vamp-simple-host.exe' [disabled].
  # build_fftw # Uses dlfcn.
  # build_libsamplerate # Needs libsndfile >= 1.0.6 and fftw >= 0.15.0 for tests. Uses dlfcn.
  build_librubberband # How to use the bundled libraries '-DUSE_SPEEX' and '-DUSE_KISSFFT'?
  if [[ "$bits_target" != "32" ]]; then
    if [[ $build_svt_hevc = y ]]; then
      build_svt-hevc
    fi
    if [[ $build_svt_vp9 = y ]]; then
      build_svt-vp9
    fi
    build_svt-av1
  fi
  build_vidstab
  build_libmysofa # Needed for FFmpeg's SOFAlizer filter (https://ffmpeg.org/ffmpeg-filters.html#sofalizer). Uses dlfcn.
  if [[ "$non_free" = "y" ]]; then
    build_fdk-aac # Uses dlfcn.
    if [[ $compiler_flavors != "native" ]]; then
	 build_AudioToolboxWrapper # This wrapper library enables FFmpeg to use AudioToolbox codecs on Windows, with DLLs shipped with iTunes.
      build_libdecklink # Error finding rpc.h in native builds even if it's available
    fi
  fi
  build_zvbi # Uses iconv, libpng and dlfcn.
  build_fribidi # Uses dlfcn.
  build_libass # Needs freetype >= 9.10.3 (see https://bugs.launchpad.net/ubuntu/+source/freetype1/+bug/78573 o_O) and fribidi >= 0.19.0. Uses fontconfig >= 2.10.92, iconv and dlfcn.
  build_libxvid # FFmpeg now has native support, but libxvid still provides a better image.
  build_libsrt # requires gnutls, mingw-std-threads
  if [[ $ffmpeg_git_checkout_version != *"n6.0"* ]] && [[ $ffmpeg_git_checkout_version != *"n5"* ]] && [[ $ffmpeg_git_checkout_version != *"n4"* ]] && [[ $ffmpeg_git_checkout_version != *"n3"* ]] && [[ $ffmpeg_git_checkout_version != *"n2"* ]]; then 
    build_libaribcaption
  fi
  build_libaribb24
  build_libtesseract
  build_lensfun  # requires png, zlib, iconv
  # if [[ $compiler_flavors != "native" ]]; then
    # install_libtensorflow # requires tensorflow.dll; find in redist folder with frei0r plugins
  # fi	
  build_libvpx
  build_libx265
  build_libopenh264
  build_libaom
  build_dav1d
  if [[ $OSTYPE != darwin* ]]; then
    build_vulkan
    build_libplacebo
  fi
  # build_whisper # Can use vulkan or openCL, uses spirv-headers, can use openblas, find ggml databases in redist folder
  build_opencv # Uses tiff png jpeg zlib webp openCL, can use vulkan
  build_frei0r # Needs dlfcn. Uses opencv. 	
  build_avisynth
  build_libvvenc
  build_libvvdec
  build_libx264 # at bottom as it might internally build a copy of ffmpeg (which needs all the above deps...
 }

build_apps() {
  if [[ $build_dvbtee = "y" ]]; then
    build_dvbtee_app
  fi
  # now the things that use the dependencies...
  if [[ $build_libmxf = "y" ]]; then
    build_libMXF
  fi
  if [[ $build_mp4box = "y" ]]; then
    build_mp4box
  fi
  if [[ $build_mplayer = "y" ]]; then
    build_mplayer
  fi
  if [[ $build_ffmpeg_static = "y" ]]; then
    build_ffmpeg static
  fi
  if [[ $build_ffmpeg_shared = "y" ]]; then
    build_ffmpeg shared
  fi
  if [[ $build_vlc = "y" ]]; then
    build_vlc
  fi
  if [[ $build_lsw = "y" ]]; then
    build_lsw
  fi
}

# set some parameters initial values
top_dir="$(pwd)"
cur_dir="$(pwd)/sandbox"
patch_dir="$(pwd)/patches"
cpu_count="$(grep -c processor /proc/cpuinfo 2>/dev/null)" # linux cpu count
core_count="$(grep 'core id' /proc/cpuinfo | sort -u | wc -l)" # linux core count
if [ -z "$cpu_count" ]; then
  cpu_count=`sysctl -n hw.ncpu | tr -d '\n'` # OS X cpu count
  if [ -z "$cpu_count" ]; then
    echo "warning, unable to determine cpu count, defaulting to 1"
    cpu_count=1 # else default to just 1, instead of blank, which means infinite
  fi
fi

set_box_memory_size_bytes
if [[ $box_memory_size_bytes -lt 600000000 ]]; then
  echo "your box only has $box_memory_size_bytes, 512MB (only) boxes crash when building cross compiler gcc, please add some swap" # 1G worked OK however...
  exit 1
fi

if [[ $box_memory_size_bytes -gt 2000000000 ]]; then
  gcc_cpu_count=$cpu_count # they can handle it seemingly...
else
  echo "low RAM detected so using only one cpu for gcc compilation"
  gcc_cpu_count=1 # compatible low RAM...
fi

# variables with their defaults
build_ffmpeg_static=y
build_ffmpeg_shared=n
build_dvbtee=n
build_libmxf=n
build_mp4box=n
build_mplayer=n
build_vlc=n
build_lsw=n # To build x264 with L-Smash-Works.
build_dependencies=y
git_get_latest=y
prefer_stable=y # Only for x264 and x265.
build_intel_qsv=y # libvpl 
build_amd_amf=y
disable_nonfree=y # comment out to force user y/n selection
original_cflags='-mtune=generic -O2 -pipe' 
original_cxxflags='-mtune=generic -O2 -pipe' 
original_cppflags='-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3' 
# if you specify a march it needs to first so x264's configure will use it :| [ is that still the case ?]
#flags=$(cat /proc/cpuinfo | grep flags)
#if [[ $flags =~ "ssse3" ]]; then # See https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html, https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html and https://stackoverflow.com/questions/19689014/gcc-difference-between-o3-and-os.

ffmpeg_git_checkout_version=n8.1.2
build_ismindex=n
enable_gpl=y
build_x264_with_libav=n # To build x264 with Libavformat.
ffmpeg_git_checkout="https://github.com/FFmpeg/FFmpeg.git"
ffmpeg_source_dir=
build_svt_hevc=n
build_svt_vp9=n

# parse command line parameters, if any
while true; do
  case $1 in
    -h | --help ) echo "available option=default_value:
      --build-ffmpeg-static=y  (ffmpeg.exe, ffplay.exe and ffprobe.exe)
      --build-ffmpeg-shared=n  (ffmpeg.exe (with libavformat-x.dll, etc., ffplay.exe, ffprobe.exe and dll-files)
      --ffmpeg-git-checkout-version=[master] if you want to build a particular version of FFmpeg, ex: n3.1.1 or a specific git hash
      --ffmpeg-git-checkout=[https://github.com/FFmpeg/FFmpeg.git] if you want to clone FFmpeg from other repositories
      --ffmpeg-source-dir=[default empty] specifiy the directory of ffmpeg source code. When specified, git will not be used.
      --x265-git-checkout-version=[master] if you want to build a particular version of x265, ex: --x265-git-checkout-version=Release_3.2 or a specific git hash
      --fdk-aac-git-checkout-version= if you want to build a particular version of fdk-aac, ex: --fdk-aac-git-checkout-version=v2.0.1 or another tag
      --gcc-cpu-count=[cpu_cores_on_box if RAM > 1GB else 1] number of cpu cores this speeds up initial cross compiler build.
      --build-cpu-count=[cpu_cores_on_box] set to lower than your cpu cores if the background processes eating all your cpu bugs your desktop usage
      --disable-nonfree=y (set to n to include nonfree like libfdk-aac,decklink)
      --build-intel-qsv=y (set to y to include the [non windows xp compat.] qsv library and ffmpeg module. NB this not not hevc_qsv...
      --sandbox-ok=n [skip sandbox prompt if y]
      -d [meaning \"defaults\" skip all prompts, just build ffmpeg static 64 bit with some defaults for speed like no git updates]
      --build-libmxf=n [builds libMXF, libMXF++, writeavidmxfi.exe and writeaviddv50.exe from the BBC-Ingex project]
      --build-mp4box=n [builds MP4Box.exe from the gpac project]
      --build-mplayer=n [builds mplayer.exe and mencoder.exe]
      --build-vlc=n [builds a [rather bloated] vlc.exe]
      --build-lsw=n [builds L-Smash Works VapourSynth and AviUtl plugins]
      --build-ismindex=n [builds ffmpeg utility ismindex.exe]
      -a 'build all' builds ffmpeg, mplayer, vlc, etc. with all fixings turned on [many disabled from disuse these days]
      --build-svt-hevc=n [builds libsvt-hevc modules within ffmpeg etc.]
      --build-svt-vp9=n [builds libsvt-hevc modules within ffmpeg etc.]
      --build-dvbtee=n [build dvbtee.exe a DVB profiler]
      --compiler-flavors=[multi,win32,win64,native] [default prompt, or skip if you already have one built, multi is both win32 and win64]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --git-get-latest=y [do a git pull for latest code from repositories like FFmpeg--can force a rebuild if changes are detected]
      --build-x264-with-libav=n build x264.exe with bundled/included "libav" ffmpeg libraries within it
      --prefer-stable=y build a few libraries from releases instead of git master
      --debug Make this script  print out each line as it executes
      --enable-gpl=[y] set to n to do an lgpl build
      --build-dependencies=y [builds the ffmpeg dependencies. Disable it when the dependencies was built once and can greatly reduce build time. ]
       "; exit 0 ;;
    --sandbox-ok=* ) sandbox_ok="${1#*=}"; shift ;;
    --gcc-cpu-count=* ) gcc_cpu_count="${1#*=}"; shift ;;
    --build-cpu-count=* ) cpu_count="${1#*=}"; shift ;;
    --ffmpeg-git-checkout-version=* ) ffmpeg_git_checkout_version="${1#*=}"; shift ;;
    --ffmpeg-git-checkout=* ) ffmpeg_git_checkout="${1#*=}"; shift ;;
    --ffmpeg-source-dir=* ) ffmpeg_source_dir="${1#*=}"; shift ;;
    --x265-git-checkout-version=* ) x265_git_checkout_version="${1#*=}"; shift ;;
    --fdk-aac-git-checkout-version=* ) fdk_aac_git_checkout_version="${1#*=}"; shift ;;
    --build-libmxf=* ) build_libmxf="${1#*=}"; shift ;;
    --build-mp4box=* ) build_mp4box="${1#*=}"; shift ;;
    --build-ismindex=* ) build_ismindex="${1#*=}"; shift ;;
    --git-get-latest=* ) git_get_latest="${1#*=}"; shift ;;
    --build-amd-amf=* ) build_amd_amf="${1#*=}"; shift ;;
    --build-intel-qsv=* ) build_intel_qsv="${1#*=}"; shift ;;
    --build-x264-with-libav=* ) build_x264_with_libav="${1#*=}"; shift ;;
    --build-mplayer=* ) build_mplayer="${1#*=}"; shift ;;
    --cflags=* )
       original_cflags="${1#*=}"; echo "setting cflags as $original_cflags"; shift ;;
    --build-vlc=* ) build_vlc="${1#*=}"; shift ;;
    --build-lsw=* ) build_lsw="${1#*=}"; shift ;;
    --build-dvbtee=* ) build_dvbtee="${1#*=}"; shift ;;
    --disable-nonfree=* ) disable_nonfree="${1#*=}"; shift ;;
    # this doesn't actually "build all", like doesn't build 10 high-bit LGPL ffmpeg, but it does exercise the "non default" type build options...
    -a         ) compiler_flavors="multi"; build_mplayer=n; build_libmxf=y; build_mp4box=n; build_vlc=y; build_lsw=n;
                 build_ffmpeg_static=y; build_ffmpeg_shared=y; disable_nonfree=n; git_get_latest=y;
                 sandbox_ok=y; build_amd_amf=y; build_intel_qsv=y; build_dvbtee=y; build_x264_with_libav=y; shift ;;
    --build-svt-hevc=* ) build_svt_hevc="${1#*=}"; shift ;;
    --build-svt-vp9=* ) build_svt_vp9="${1#*=}"; shift ;;
    -d         ) echo "defaults: doing 64 bit only, fast"; gcc_cpu_count=$cpu_count; disable_nonfree="y"; sandbox_ok="y"; compiler_flavors="win64"; git_get_latest="n"; shift ;;
    --compiler-flavors=* )
         compiler_flavors="${1#*=}";
         if [[ $compiler_flavors == "native" && $OSTYPE == darwin* ]]; then
           build_intel_qsv=n
           echo "disabling qsv since os x"
         fi
         shift ;;
    --build-ffmpeg-static=* ) build_ffmpeg_static="${1#*=}"; shift ;;
    --build-ffmpeg-shared=* ) build_ffmpeg_shared="${1#*=}"; shift ;;
    --prefer-stable=* ) prefer_stable="${1#*=}"; shift ;;
    --enable-gpl=* ) enable_gpl="${1#*=}"; shift ;;
    --build-dependencies=* ) build_dependencies="${1#*=}"; shift ;;
    --debug ) set -x; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

original_cpu_count=$cpu_count # save it away for some that revert it temporarily
reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
reset_cppflags # Ensure CPPFLAGS are cleared and set to what is configured
reset_cxxflags # Ensure CXXFLAGS are cleared and set to what is configured
check_missing_packages # do this first since it's annoying to go through prompts then be rejected
intro # remember to always run the intro, since it adjust pwd
install_cross_compiler

export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]

if [[ $OSTYPE == darwin* ]]; then
  # mac add some helper scripts
  mkdir -p mac_helper_scripts
  cd mac_helper_scripts
    if [[ ! -x readlink ]]; then
      # make some scripts behave like linux...
      curl -4 file://$patch_dir/md5sum.mac --fail > md5sum  || exit 1
      chmod u+x ./md5sum
      curl -4 file://$patch_dir/readlink.mac --fail > readlink  || exit 1
      chmod u+x ./readlink
    fi
    export PATH=`pwd`:$PATH
  cd ..
fi

original_path="$PATH"

if [[ $compiler_flavors == "native" ]]; then
  echo "starting native build..."
  # realpath so if you run it from a different symlink path it doesn't rebuild the world...
  # mkdir required for realpath first time
  mkdir -p $cur_dir/native
  mkdir -p $cur_dir/native/bin
  x86_64_prefix="$(realpath $cur_dir/native)"
  bin_path="$(realpath $cur_dir/native/bin)" # sdl needs somewhere to drop "binaries"??
  export PKG_CONFIG_PATH="$x86_64_prefix/lib/pkgconfig"
  export PATH="$bin_path:$original_path"
  make_prefix_options="PREFIX=$x86_64_prefix"
  if [[ $(uname -m) =~ 'i686' ]]; then
    bits_target=32
  else
    bits_target=64
  fi
  #  bs2b doesn't use pkg-config, sndfile needed Carbon :|
  export CPATH=$cur_dir/native/include:/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Headers # C_INCLUDE_PATH
  export LIBRARY_PATH=$cur_dir/native/lib
  work_dir="$(realpath $cur_dir/native)"
  mkdir -p "$work_dir"
  cd "$work_dir"
    build_ffmpeg_dependencies
    build_ffmpeg
  cd ..
fi

if [[ $compiler_flavors == "multi" || $compiler_flavors == "win32" ]]; then
  echo
  echo "Starting 32-bit builds..."
  host_target='i686-w64-mingw32'
  mkdir -p $cur_dir/mingw-w64-i686/$host_target
  x86_64_prefix="$(realpath $cur_dir/mingw-w64-i686/$host_target)"
  mkdir -p $cur_dir/cross_compilers/mingw-w64-i686/bin
  bin_path="$(realpath $cur_dir/mingw-w64-i686/bin)"
  export PKG_CONFIG_PATH="$x86_64_prefix/lib/pkgconfig"
  export PATH="$bin_path:$original_path"
  bits_target=32
  cross_prefix="$bin_path/i686-w64-mingw32-"
  make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
  work_dir="$(realpath $cur_dir/win32)"
  mkdir -p "$work_dir"
  cd "$work_dir"
    build_ffmpeg_dependencies
    build_apps
  cd ..
fi

if [[ $compiler_flavors == "multi" || $compiler_flavors == "win64" ]]; then
  echo
  echo "**************Starting 64-bit builds..." # make it have a bit easier to you can see when 32 bit is done
  host_target='x86_64-w64-mingw32'
  mkdir -p $cur_dir/x86_64/$host_target
  x86_64_prefix="$(realpath $cur_dir/x86_64/$host_target)"
  mkdir -p $cur_dir/x86_64/bin
  bin_path="$(realpath $cur_dir/x86_64/bin)"
  export PKG_CONFIG_PATH="$x86_64_prefix/lib/pkgconfig"
  export PATH="$bin_path:$original_path"
  bits_target=64
  cross_prefix="$bin_path/x86_64-w64-mingw32-"
  make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++ FC=${cross_prefix}gfortran CUDACXX=nvcc"
  work_dir="$(realpath $cur_dir/win64)"
  mkdir -p "$work_dir"
  cd "$work_dir"
    build_ffmpeg_dependencies
    build_apps
  cd ..
fi

echo "searching for all local exe's (some may not have been built this round, NB)..."
for file in $(find_all_build_exes); do
  echo "built $file"
done
mv $x86_64_prefix/bin/ff{mpeg,play,probe}.exe $HOME/sandbox/redist
