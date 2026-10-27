# Android.mk for the AOSP platform/external/sqlite `dist' tree, written
# for GNU Emacs's ndk-build-compatible dependency system (see
# java/INSTALL, "BUILDING WITH THIRD PARTY LIBRARIES").  AOSP main ships
# only Android.bp; this file mirrors the `sqlite-minimal-defaults' and
# android target cflags from that file, minus -Werror and the
# -ftrivial-auto-var-init option, and exports the header directory so
# configure's sqlite3.h declaration check succeeds.  Emacs's configure
# maps the pkg-config name `sqlite3' to the module name below.
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := libsqlite_static_minimal
LOCAL_SRC_FILES := sqlite-autoconf-3440400/sqlite3.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/sqlite-autoconf-3440400
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/sqlite-autoconf-3440400
LOCAL_CFLAGS += -DNDEBUG=1 -DHAVE_USLEEP=1 -DSQLITE_HAVE_ISNAN \
  -DSQLITE_DEFAULT_JOURNAL_SIZE_LIMIT=1048576 -DSQLITE_THREADSAFE=2 \
  -DSQLITE_TEMP_STORE=3 -DSQLITE_POWERSAFE_OVERWRITE=1 \
  -DSQLITE_DEFAULT_FILE_FORMAT=4 -DSQLITE_DEFAULT_AUTOVACUUM=1 \
  -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_MEMORY_MANAGEMENT=1 \
  -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_BACKWARDS -DSQLITE_ENABLE_FTS4 \
  -DSQLITE_OMIT_BUILTIN_TEST -DSQLITE_OMIT_COMPILEOPTION_DIAGS \
  -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_DEFAULT_FILE_PERMISSIONS=0600 \
  -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_BATCH_ATOMIC_WRITE \
  -DBIONIC_IOCTL_NO_SIGNEDNESS_OVERLOAD -DSQLITE_DEFAULT_LEGACY_ALTER_TABLE \
  -DSQLITE_ALLOW_ROWID_IN_VIEW -DSQLITE_ENABLE_BYTECODE_VTAB \
  -DUSE_PREAD64 -Dfdatasync=fdatasync -DHAVE_MALLOC_H=1 \
  -Wno-unused-parameter
include $(BUILD_STATIC_LIBRARY)
