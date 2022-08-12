#!/usr/bin/perl -w
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright 2010 - Steven Rostedt <srostedt@redhat.com>, Red Hat Inc.
#

use strict;
use IPC::Open2;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use File::Path qw(mkpath);
use File::Copy qw(cp);
use FileHandle;
use FindBin;
use IO::Handle;

my $VERSION = "0.2";

$| = 1;

my %opt;
my %repeat_tests;
my %repeats;
my %evals;

#default opts
my %default = (
    "MAILER"			=> "sendmail",	# default mailer
    "EMAIL_ON_ERROR"		=> 1,
    "EMAIL_WHEN_FINISHED"	=> 1,
    "EMAIL_WHEN_CANCELED"	=> 0,
    "EMAIL_WHEN_STARTED"	=> 0,
    "NUM_TESTS"			=> 1,
    "TEST_TYPE"			=> "build",
    "BUILD_TYPE"		=> "oldconfig",
    "MAKE_CMD"			=> "make",
    "CLOSE_CONSOLE_SIGNAL"	=> "INT",
    "TIMEOUT"			=> 120,
    "TMP_DIR"			=> "/tmp/ktest/\${MACHINE}",
    "SLEEP_TIME"		=> 60,		# sleep time between tests
    "BUILD_NOCLEAN"		=> 0,
    "REBOOT_ON_ERROR"		=> 0,
    "POWEROFF_ON_ERROR"		=> 0,
    "REBOOT_ON_SUCCESS"		=> 1,
    "POWEROFF_ON_SUCCESS"	=> 0,
    "BUILD_OPTIONS"		=> "",
    "BISECT_SLEEP_TIME"		=> 60,		# sleep time between bisects
    "PATCHCHECK_SLEEP_TIME"	=> 60, 		# sleep time between patch checks
    "CLEAR_LOG"			=> 0,
    "BISECT_MANUAL"		=> 0,
    "BISECT_SKIP"		=> 1,
    "BISECT_TRIES"		=> 1,
    "MIN_CONFIG_TYPE"		=> "boot",
    "SUCCESS_LINE"		=> "login:",
    "DETECT_TRIPLE_FAULT"	=> 1,
    "NO_INSTALL"		=> 0,
    "BOOTED_TIMEOUT"		=> 1,
    "DIE_ON_FAILURE"		=> 1,
    "SSH_EXEC"			=> "ssh \$SSH_USER\@\$MACHINE \$SSH_COMMAND",
    "SCP_TO_TARGET"		=> "scp \$SRC_FILE \$SSH_USER\@\$MACHINE:\$DST_FILE",
    "SCP_TO_TARGET_INSTALL"	=> "\${SCP_TO_TARGET}",
    "REBOOT"			=> "ssh \$SSH_USER\@\$MACHINE reboot",
    "REBOOT_RETURN_CODE"	=> 255,
    "STOP_AFTER_SUCCESS"	=> 10,
    "STOP_AFTER_FAILURE"	=> 60,
    "STOP_TEST_AFTER"		=> 600,
    "MAX_MONITOR_WAIT"		=> 1800,
    "GRUB_REBOOT"		=> "grub2-reboot",
    "GRUB_BLS_GET"		=> "grubby --info=ALL",
    "SYSLINUX"			=> "extlinux",
    "SYSLINUX_PATH"		=> "/boot/extlinux",
    "CONNECT_TIMEOUT"		=> 25,

# required, and we will ask users if they don't have them but we keep the default
# value something that is common.
    "REBOOT_TYPE"		=> "grub",
    "LOCALVERSION"		=> "-test",
    "SSH_USER"			=> "root",
    "BUILD_TARGET"	 	=> "arch/x86/boot/bzImage",
    "TARGET_IMAGE"		=> "/boot/vmlinuz-test",

    "LOG_FILE"			=> undef,
    "IGNORE_UNUSED"		=> 0,
);

my $test_log_start = 0;

my $ktest_config = "ktest.conf";
my $version;
my $have_version = 0;
my $machine;
my $last_machine;
my $ssh_user;
my $tmpdir;
my $builddir;
my $outputdir;
my $output_config;
my $test_type;
my $build_type;
my $build_options;
my $final_post_ktest;
my $pre_ktest;
my $post_ktest;
my $pre_test;
my $pre_test_die;
my $post_test;
my $pre_build;
my $post_build;
my $pre_build_die;
my $post_build_die;
my $reboot_type;
my $reboot_script;
my $power_cycle;
my $reboot;
my $reboot_return_code;
my $reboot_on_error;
my $switch_to_good;
my $switch_to_test;
my $poweroff_on_error;
my $reboot_on_success;
my $die_on_failure;
my $powercycle_after_reboot;
my $poweroff_after_halt;
my $max_monitor_wait;
my $ssh_exec;
my $scp_to_target;
my $scp_to_target_install;
my $power_off;
my $grub_menu;
my $last_grub_menu;
my $grub_file;
my $grub_number;
my $grub_reboot;
my $grub_bls_get;
my $syslinux;
my $syslinux_path;
my $syslinux_label;
my $target;
my $make;
my $pre_install;
my $post_install;
my $no_install;
my $noclean;
my $minconfig;
my $start_minconfig;
my $start_minconfig_defined;
my $output_minconfig;
my $minconfig_type;
my $use_output_minconfig;
my $warnings_file;
my $ignore_config;
my $ignore_errors;
my $addconfig;
my $in_bisect = 0;
my $bisect_bad_commit = "";
my $reverse_bisect;
my $bisect_manual;
my $bisect_skip;
my $bisect_tries;
my $config_bisect_good;
my $bisect_ret_good;
my $bisect_ret_bad;
my $bisect_ret_skip;
my $bisect_ret_abort;
my $bisect_ret_default;
my $in_patchcheck = 0;
my $run_test;
my $buildlog;
my $testlog;
my $dmesg;
my $monitor_fp;
my $monitor_pid;
my $monitor_cnt = 0;
my $sleep_time;
my $bisect_sleep_time;
my $patchcheck_sleep_time;
my $ignore_warni