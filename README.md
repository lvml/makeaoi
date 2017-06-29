
# makeaoi - Make Application Overlay Image

## Purpose

makeaoi is meant to address the following use case:

* You want to run Linux application X on a system B, where it is not yet available. But X runs fine on some Linux system A. 
* Systems A and B do not run identical operating system distribtions or versions thereof.
* Compilation or installation of application X on system B would be cumbersome if not impossible - for example, because system B is lacking a lot of pre-requisites, or because you only have non-root access to system B.

makeaoi can be run as an unprivileged user on system A, it will find all the relevant files required to run one or multiple executables there by tracing them, then it will prepare a directory that contains all these files plus a script to mount this directory as an "overlay" to the "/" filesystem (using unionfs-fuse, which does not require root privileges), and thus you should be able to start application X on any system B by invoking the created start script.

Notice that no re-compilation of anything is involved here. 

makeaoi is not a "software package maintainer tool", as such you would probably rather try to compile a version using relative paths, on a fairly "old" system which hopefully results in executables that could be run on most (and newer) systems.

The directory prepared by makeaoi will include "everything", from the ELF interpreter "ld-linux" to "libc.so.*" and the timezone definition files. So unlike a specifically compiled package the makeaoi result directory will be fairly large - but probably not as large as you might fear.

To give you an example: I initially implemented "makeaoi" because I wanted to run "RawTherapee 5.1" on some CentOS system that had not quite the many prerequisites available required by RawTherapee 5.1 - and compilation attempts turned into a bottomless dependency hellhole. So I ran "makeaoi" on some Arch linux system, and packaged the resulting directory into an AppImage - which was 80MB in size, which is absolutely fine with me.

## Prerequisites

On system A, where you want to prepare the directory, a number of common Unix tools are required, which should be provided by most distributions anyway:

* "which"
* "ln"
* "patchelf"
* "taskset"  (optional but recommended)
* "strace"
* "cat"
* "convert"  (optional)
* "tar"
* "grep"
* "tail"
* "base64"
* "gzip"

On system B, where you want to run the applications from the prepared directory, you will need at least:

* /bin/bash
* A non-ancient linux kernel. If CONFIG_USER_NS was enabled in the kernel ".config", then the executables can be started without any privileges - this is the only recommended mode. If user namespaces are not enabled in the kernel of system B, you can modify the "AppRun" script in the result directory to name a user and group to actually use for the execution, but you will need to start the AppRun scripts (directly or via the soft links) as root. This is really awkward and not recommended.

## Installation

Run

    git clone https://github.com/lvml/makeaoi
    cd makeaoi
    make

to create "makeaoi" - the make just appends some base64-encoded binary data to
the "makeaoi.tcl" script, to make it self-contained.

You can either copy the self-contained "makeaoi" script anywhere, or you can run "makeaoi.tcl" directly, but in that case, the "makeaoi_aux" directory has to be present in the same directory as "makeaoi.tcl".

## Usage

### "Hello World" example

Let's assume you are a happy user of "xeyes" and "xrender" on system A, and want to run these on system B.

On system A, in some shell, type

    makeaoi trace /tmp/sample xeyes

and read the output for useful hints. Close the "xeyes" window to make "xeyes" exit gracefully.

Next, type

	makeaoi trace /tmp/sample xrender
	
and like above, close its window.

Then, type

   makeaoi populate /tmp/sample
	
and again read the terminal output for useful hints.

This should get you a directory named /tmp/sample, which contains everything required to run xeyes or xrender.

Transfer this directory to your system B, for example via

   tar -C /tmp -c -f - sample | ssh you@B "tar -C /home/you/ -x -v -f -"

Then, on system B, invoke

   /home/you/sample/xeyes
	/home/you/sample/xrender
	
You get the idea.

### Preparing AppImages from makeaoi-generated directories

AppImage is a format for packaging a directory with everything needed for an application into a self-extracting executable.
makeaoi automatically creates the minimum set of files required in such a directory to make the "appimagetool" happy.

So for above example, you could run

    cd /tmp/
	 appimagetool --comp xz --no-appstream sample

and then transfer/invoke the resulting AppImage file on system B.


## Caveats

There is plenty to write here, but not yet done :-)
