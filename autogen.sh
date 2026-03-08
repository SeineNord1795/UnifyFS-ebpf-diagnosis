#!/bin/sh

echo
echo ... UnifyFS autogen ...
echo

# --------- 关键增强：确保本地 m4/ 存在，并让 aclocal 能找到它 ---------
# 很多 autotools 项目约定把自定义宏放在 ./m4
# 没有这个目录时，有些环境会报 warning，甚至宏解析失败
if [ ! -d "m4" ]; then
  mkdir -p m4 || exit 1
fi

# 把项目的 m4/ 加进 aclocal 搜索路径（ACLOCAL_FLAGS 兼容常见做法）
# 你也可以在外部 export ACLOCAL_FLAGS="-I m4" 来覆盖
ACLOCAL_FLAGS="${ACLOCAL_FLAGS:--I m4}"
# --------------------------------------------------------------------

## Check all dependencies are present
MISSING=""

# Check for aclocal
env aclocal --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
  ACLOCAL=aclocal
else
  MISSING="$MISSING aclocal"
fi

# Check for autoconf
env autoconf --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
  AUTOCONF=autoconf
else
  MISSING="$MISSING autoconf"
fi

# Check for autoheader
env autoheader --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
  AUTOHEADER=autoheader
else
  MISSING="$MISSING autoheader"
fi

# Check for automake
env automake --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
  AUTOMAKE=automake
else
  MISSING="$MISSING automake"
fi

# Check for libtoolize or glibtoolize
env libtoolize --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
  LIBTOOLIZE=libtoolize
else
  env glibtoolize --version > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    LIBTOOLIZE=glibtoolize
  else
    MISSING="$MISSING libtoolize"
  fi
fi

# Check for tar
env tar -cf /dev/null /dev/null > /dev/null 2>&1
if [ $? -ne 0 ]; then
  MISSING="$MISSING tar"
fi

## If dependencies are missing, warn the user and abort
if [ "x$MISSING" != "x" ]; then
  echo "Aborting."
  echo
  echo "The following build tools are missing:"
  echo
  for pkg in $MISSING; do
    echo "  * $pkg"
  done
  echo
  echo "Please install them and try again."
  echo
  exit 1
fi

## Do the autogeneration
env autoreconf --version > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo Running ${LIBTOOLIZE}...
  $LIBTOOLIZE --automake --copy --force
  echo Running autoreconf...
  autoreconf --force --install --verbose
else
  echo Running ${LIBTOOLIZE}...
  $LIBTOOLIZE --automake --copy --force
  echo Running ${ACLOCAL}...
  $ACLOCAL $ACLOCAL_FLAGS
  echo Running ${AUTOHEADER}...
  $AUTOHEADER
  echo Running ${AUTOCONF}...
  $AUTOCONF
  echo Running ${AUTOMAKE}...
  $AUTOMAKE --add-missing --force-missing --copy --foreign
fi

echo
echo "Please proceed with configuring, compiling, and installing."