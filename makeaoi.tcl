#!/usr/bin/tclsh
 
proc syntax {} {
	
	puts stderr {
makeaoi - "Make Application Overlay Image"
written by Lutz Vieweg <lvml@5t9.de>

Invocation:

 Use:
  makeaoi trace <aoi-directory> <executable path>
 to run an executable, tracing its accesses of files,
 which are logged into <aoi-directory>/strace.txt.
 Can be called multiple times to enhance coverage of
 potentially used files, or to add multiple executables
 to the Application Overlay Image.
 
 Next, use your favourite $EDITOR to open <aoi-directory>/files.txt,
 review the list of files that should become part of the
 application image, and save your edited file under the name
  <aoi-directory>/packlist.txt
 
 Then, use:
  makeaoi populate <aoi-directory>
 to copy all files/directories named in <aoi-directory>/packlist.txt
 into a sub-directory of <aoi-directory> that will become the
 "root"-filesystem overlay.
 This also copies statically linked helper-tools and a start script
 into <aoi-directory>, and will create some default icon, in order
 to prepare everything necessary to use the "appimage" tool to
 create an AppImage from the <aoi-directory>
 
 
}
}

set subcmd [lindex $argv 0]
set aoidir [lindex $argv 1]

if {![file isdirectory $aoidir]} {
	# try to make it
	file mkdir $aoidir
}

set tracelog "$aoidir/strace.txt"
set packlist "$aoidir/packlist.txt"

#########################################################################
# procedures for the trace sub-command

array set filehash {}
set files {}

array set filters {}
set filters(exclude) {
		{^/$}
		{^/home/}
		{^/home$}
		{^/etc/}
		{^/var/}
		{^/dev/}
		{^/proc/}
		{^/sys/}
		{^/run/}
		{^/tmp/}
		{^/tmp$}
}
set filters(nodirectories) {
		{^/usr/share/fonts}
		{^/usr/share/icons}
		{^/usr/share/pixmaps}
		{^/usr/share/locale}
}
set filters(generalizers) {
		{/usr/share/zoneinfo/.}
		{/usr/share/themes/.+/.}
}

proc add_nonignored_entry { fname } {
	global filehash
	global files
	global filters	
	
	set fnorm [file normalize $fname]
	
	foreach re $filters(generalizers) {
		if {[regexp "^$re" $fnorm range]} {
			set gentarget [file dirname $range]
			puts stderr "generalizing from file $fnorm to $gentarget"
			set fname $gentarget
			set fnorm [file normalize $fname]
		}
	}
	
	foreach re $filters(exclude) {
		if {[regexp $re $fnorm]} {
			# puts stderr "ignoring due to exclude filter '$re': $fnorm"
			return
		}
	}
	
	if {[file type $fname] == "directory"} {
		foreach re $filters(nodirectories) {
			if {[regexp $re $fnorm]} {
				# puts stderr "ignoring due to nodirectories filter '$re': $fnorm"
				return
			}
		}		
	}
	
	if {![info exists filehash($fnorm)]} {
		set filehash($fnorm) 1
		lappend files $fnorm
	}
}

proc add_file_or_links { fname } {
	
	while {1} {
		
		set fsd ""
		foreach fs [file split [file dirname $fname]] {
			# if any of the directories leading to $fname is a symlink,
			# we need to list it
			set fsd [file join $fsd $fs]
			if {[catch {set ft [file type $fsd]}]} {
				puts stderr "directory '$fsd' no longer exists - ignoring"
				continue
			}
			if {$ft == "link"} {
				add_nonignored_entry $fsd
			}
		}
		
		add_nonignored_entry $fname
		
		if {[file type $fname] != "link"} {
			break;
		}
		
		set fname [file join [file dirname $fname] [file readlink $fname]]
	}
}

#########################################################################
# main

if {$subcmd == "trace" } {
	set exe [lindex $argv 2]

	# add the supplied executable to files.txt 
	set exep [exec which $exe 2>@stderr]
	add_file_or_links $exep

	# create a link from the executable name to the "AppRun" script,
	# such that users can call multiple executables via this "AppRun" script
	set scriptlinkname "$aoidir/[file tail $exe]"
	if {![file exists $scriptlinkname]} {
		exec ln -s "AppRun" $scriptlinkname  >@stdout 2>@stderr
	}
	# also create a link that is used to store the path of the actual
	# executable inside the overlay root filesystem - this link will
	# point to an existing file after the unionfs has been mounted
	set exelinkname "$aoidir/exe_[file tail $exe]"
	if {![file exists $exelinkname]} {
		exec ln -s $exep $exelinkname >@stdout 2>@stderr
	}
	# If "AppRun" is later called directly, not via one of the symbolic
	# links (as would be default action if an AppImage was created from
	# the directory), assume that the very first executable that was traced
	# is the one to be started. We remember its path in a default softlink.
	set deflinkname "$aoidir/exe_AppRun"
	if {![file exists $deflinkname]} {
		exec ln -s $exep $deflinkname  >@stdout 2>@stderr
	}


	# ELF-executables need an "interpreter" to run, add this also to files.txt
	set interp ""
	catch {set interp [exec patchelf --print-interpreter $exep 2>@stderr]}
	if {$interp == ""} {
		puts stderr "'$exep' does not seem to be an ELF executable - not adding interpreter file"
	} else {
		add_file_or_links $interp
	}

	puts stderr "running '$exep' on one CPU core under 'strace'...\n"

	# run the executable, using strace to see which files are used
	catch {exec taskset 1 strace -f -o "$tracelog.tmp" -qq \
		 -e trace=open,execve -v $exep \
	    >@stdout 2>@stderr
	}

	puts stderr "\nfinished running '$exep'"
	puts stderr "parsing strace output...\n"

	# append output of recent trace to the whole trace file
	exec cat "$tracelog.tmp" >>$tracelog 2>@stderr
	file delete "$tracelog.tmp"

	set in [open $tracelog "r"]
	while {![eof $in]} {
		set l [gets $in]
		if {$l == ""} {
			# ignore blank lines
			continue
		}

		if {![regexp {[0-9]+ *open\(\"([^"]+)\", [^)]*\) *= ([^ ]+)} $l range fname result]} {
			# " - this comment is just to make syntax-highlighting happy 


			if {![regexp {[0-9]+ *execve\(\"([^"]+)\", [^)]*} $l range fname]} {
				puts stderr "ignoring unparsesable strace output line: $l"
				continue
			}
			# execve does not return - let's pretend it does succeed:
			set result 0
		} 

		if {$result < 0} {
			# ignore files that could not be opened
			continue
		}

		if {[catch {set ft [file type $fname]}]} {
			puts stderr "file '$fname' no longer exists - ignoring"
			continue
		}

		if {$ft != "file" && $ft != "directory" && $ft != "link"} {
			puts stderr "ignoring $ft named '$fname'"
			continue
		}

		add_file_or_links $fname	
	}

	close $in

	set fsorted [lsort -dictionary -increasing $files]

	set output "$aoidir/files.txt"

	puts stderr "\ncreating '$output'"

	set out [open $output "w"]
	foreach f $fsorted {
		puts $out $f
	}
	close $out

	puts stderr "makeaoi trace finished.\n"
	puts stderr "Now either run another 'makeaoi trace $aoidir <some_executable>',"
	puts stderr "or use your favourite \$EDITOR to review $output"
	puts stderr "and save your edited file as '$aoidir/packlist.txt'.\n"		
	puts stderr "After you created '$aoidir/packlist.txt', you can run"
	puts stderr "'makeaoi populate $aoidir'.\n"		
	exit 0
}
	
################################# populate ############################
if {$subcmd == "populate"} {
		
	# Get default executable name from the content of the default softlink.
	# This is only used for naming things in config files that make appimagetool
	# happy, should that later be used.
	set exename [file tail [file link "$aoidir/exe_AppRun"]]

	set rdir "$aoidir/root_overlay"
	# create the root overlay directory, if not already existent
	if {![file isdirectory $rdir]} {
		file mkdir $rdir
	}
	
	# create some default ".desktop" file to make appimagetool happy,
	# should that later be used
	set dtfile "$aoidir/${exename}.desktop"
	if {![file isfile $dtfile]} {
		puts stderr "creating file $dtfile"
		set out [open $dtfile "w"]
		puts $out "\[Desktop Entry\]"
		puts $out "Type=Application"
		puts $out "Name=${exename}"
		puts $out "Exec=AppRun"
		puts $out "Icon=${exename}"
		puts $out "Categories=Utility"
		close $out
	}

	# create some default icon file to make appimagetool happy,
	# should that later be used
	set logoname "$aoidir/${exename}.png"
	if {![file isfile $logoname]} {
		puts stderr "creating a default icon in $logoname"
		exec convert -size 400x100 -pointsize 48 "caption:$exename" $logoname \
			   >@stdout 2>@stderr
	}

	if {![file isfile $aoidir/AppRun]} {
		set asf "[file dirname [exec which $argv0]]/makeaoi_aux"
		
		puts stderr "using tar to copy support files into $aoidir/"
		if {[file isdirectory $asf]} {
			puts stderr "(Using support files from $asf, not from the base64 encoded data embedded into [info script])"
			exec tar -C $asf -c -f - . \
				   | tar -C $aoidir -x -v -f - >@stdout 2>@stderr
		} else {	
			puts stderr "(Using support files from base64 encoded data embedded at the end of [info script])"
			
			# we "grep" the base64 encoded data right from the magic-marked end of this script:
			set asfdata [exec grep -A 9999999 "p\W963GuJnrxAdWbBD2B" [info script] | tail -n +2 2>@stderr]
			exec base64 -d | tar -C $aoidir -x -z -v -f - >@stdout 2>@stderr <<$asfdata
		}
	}
	
	set apacklist "$aoidir/packlist.txt"
	if {![file exists $apacklist]} {
		puts stderr "\nThere is no $apacklist file - will continue by using"
		
		set apacklist "$aoidir/files.txt"
		puts stderr "the automatically created $apacklist file instead - "
		puts stderr "but you should really review and edit files.txt and "
		puts stderr "store your revised list as 'packlist.txt'\n"
	}
	
	puts stderr "\ncopying all files/directories named in $apacklist to $rdir\n"
	# check for --verbatim-files-from 
	exec tar -c --files-from=$apacklist -f - \
		    | tar -C $rdir -x -v -f - >@stdout 2>@stderr
	
	set mountcheckname "$rdir/aoi_supp/mount_check"
	if {![file exists $mountcheckname]} {
		
		file mkdir "$rdir/aoi_supp"
		
		# create a file of known name that allows the AppRun script to check
		# whether the unionfs was actually mounted
		set out [open "$mountcheckname" "w"]
		close $out
		
		# create a tiny helper shell script that changes into the correct
		# "current working directory" before starting the executable in the chroot
		# environment - the AOI_PWD environment variable is assigned by AppRun
		set out [open "$rdir/aoi_supp/trampoline" "w"]
		puts $out {#!/bin/bash} 
		puts $out {cd "$AOI_PWD"}
		puts $out {EXE=$1} 
		puts $out {shift} 
		puts $out {exec $EXE "$@"} 
		close $out
		file attributes "$rdir/aoi_supp/trampoline" -permissions 0755
	}


	puts stderr "\n\nYou may now remove these no longer required files:\n"
	puts stderr "rm -f \"$aoidir/strace.txt\" \"$aoidir/files.txt\"\n"
	puts stderr "You can also delete $aoidir/packlist.txt, but you may want "
	puts stderr " to retain it in there in case you want to re-run $argv0 populate $aoidir"
	puts stderr " after testing on your target system and modifying $aoidir/packlist.txt"
	
	puts stderr "\nYou could then also run"
	puts stderr "cd [file dirname $aoidir] ; appimagetool --comp xz --no-appstream [file tail $aoidir]"
	
	puts stderr ""
	exit 0
}

# none of the above matched:
puts stderr "unknown sub-command '$subcmd'"
syntax
exit 20


############# base64 encoded data for suppport binaries below #################
#
# If there is no base64 encoded data appended below, makeaoi will expect
# a directory named "makeaoi_aux" to be present in the same directory as
# makeaoi itself, and use that as a source for the "AppRun" script and
# some statically linked binaries in "aoi_support_binaries".
#
# If there is base64 encoded data appended below, makeaoi will use it if no
# "makeaoi_aux" directory is present.
#
# If you want to extract/edit the makeaoi_aux directory from a below appended
# base64 encoded text block, just "cd" to where makeaoi is stored and do
#   mkdir makeaoi_aux ; cd makeaoi_aux
#   grep -A 9999999 p\W963GuJnrxAdWbBD2B ../makeaoi | tail -n +2 | base64 -d | tar -x -z -v -f -
# to unpack these files 
#