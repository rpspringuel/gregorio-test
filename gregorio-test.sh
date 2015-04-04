#!/bin/bash

# Gregorio Tests
# Copyright (C) 2015 Gregorio Team
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Settings in $HOME/.gregorio-test.rc:
# COLOR        boolean  whether to use color by default
# VIEW_TEXT    string   the command to use to view a text file; expands {file}
#                       into the filename of the text file
# VIEW_PDF     string   the command to use to view a PDF file; expands {file}
#                       into the filename of the PDF file.
# VIEW_IMAGES  string   the command to use to view image files; expands
#                       {files} into the filenames of the image files.
# DIFF_TEXT    string   the command to use for a textual diff; expands {expect}
#                       into the filename of the expected result filename and
#                       {output} into the filename of the actual result.
# DIFF_PDF     string   the command to use for a PDF diff; expands {expect}
#                       into the filename of the expected result and {output}
#                       into the filename of the actual result.

VIEW_TEXT="cat {file}"
DIFF_TEXT="diff {expect} {output}"

rcfile=$HOME/.gregorio-test.rc
if [ -f $rcfile -a -r $rcfile ]
then
    source $rcfile
fi

case "$(echo $COLOR | tr '[:upper:]' '[:lower:]')" in
t|true|y|yes)
    color=true
    ;;
*)
    color=false
    ;;
esac

usage=false
verify=true
mode=test
while getopts ":aCdeg:hlnv" opt
do
	case $opt in
    a)
        mode=accept
        ;;
    C)
        if $color
        then
            color=false
        else
            color=true
        fi
        ;;
    d)
        mode=view_diff
        ;;
    e)
        mode=view_expected
        ;;
    g)
        gregorio_dir="$(realpath "$OPTARG")"
        ;;
    h)
        usage=true
        ;;
    l)
        mode=view_log
        ;;
    n)
        verify=false
        ;;
    v)
        mode=view_output
        ;;
    \?)
        echo "Unknown option: -$OPTARG" >&2
        echo "(use $0 -h for help)" >&2
        exit 1
        ;;
    :)
        echo "Option -$OPTARG is missing its required argument." >&2
        echo "(use $0 -h for help)" >&2
        exit 1
        ;;
	esac
done
shift $((OPTIND - 1))

if $usage
then
	columns=$(stty size | cut -d' ' -f2)
	(( columns = columns - 5 ))
	if (( columns < 50 ))
	then
		columns=50
	fi
	fmt -sw $columns <<EOT
Usage: $0 [OPTION]... [TEST]...

Runs the Gregorio test suite.  If no TEST is specified, all tests will run.

Options:

  -g GREGORIO_DIR   specifies the directory containing a not-installed
                    version of Gregorio.  For this script to be able to use
                    a not-installed Gregorio, the gregorio executable must
                    be linked statically.

  -n                runs the tests without verifying results.  Useful (in
                    conjunction with -a) for generating the initial result
                    of a new test to use as future expectation.

  -a                accepts the result of each given TEST.  Makes the result
                    into the future expectation.  Requires that at least one
                    TEST be specified.  Don't forget to add/commit the change!

  -l                views the log of the given TEST.

  -e                views the expected result of the given TEST.

  -v                views the output of the given TEST.

  -d                views the differences between the expected result and the
                    output of the given TEST.

  -C                toggles the use of color.

  -h                shows this usage message.

Note: The -a, -l, -e, -v, and -d options are mutually exclusive and will not
      work properly until after the desired test(s) are run.
EOT
	exit 1
fi

export verify

export testroot="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
cd "$testroot"

if $color
then
    C_BAD="$(tput bold 2>/dev/null; tput setaf 1 2>/dev/null)"
    C_GOOD="$(tput bold 2>/dev/null; tput setaf 2 2>/dev/null)"
    C_RESET="$(tput sgr0 2>/dev/null)"
fi

source harness.sh

if [ ! -d tests ]
then
	echo "No tests to run."
	exit 1
fi

if [ "$1" = "" ]
then
    case "$mode" in
    accept)
		echo "At least one TEST to accept must be specified." >&2
		echo "(use $0 -h for help)" >&2
		exit 4
        ;;
    view_*)
		echo "Exactly one TEST for viewing results must be specified." >&2
		echo "(use $0 -h for help)" >&2
		exit 5
        ;;
    esac

	function filter {
		while read line
		do
			echo $line
		done
	}
else
	declare -A tests_to_run
	while [ "$1" != "" ]
	do
        # strip these off in case the user is using tab-completion
        case "$1" in
            tests/*)
                arg="${1#tests/}"
                ;;
            output/*)
                arg="${1#output/}"
                ;;
            *)
                arg="$1"
                ;;
        esac

		tests_to_run[$arg]=1
		shift
	done

    case "$mode" in
    view_*)
        if [ "${#tests_to_run[@]}" != 1 ]
        then
            echo "Only one TEST for viewing results may be specified." >&2
            echo "(use $0 -h for help)" >&2
            exit 6
        fi
        ;;
    esac

	function filter {
		while read line
		do
			if [ "${tests_to_run[$line]}" = "1" ]
			then
				echo $line
			fi
		done
	}
fi

case "$mode" in
test)
	rm -fr output
	cp -r tests output

	if [ "$gregorio_dir" != "" ]
	then
		if [ ! -f "$gregorio_dir/src/gregorio" -o ! -x "$gregorio_dir/src/gregorio" ]
		then
			echo "$gregorio_dir/src/gregorio is not an executable" >&2
			exit 2
		fi

		echo "Preparing to use Gregorio from $gregorio_dir"

		export PATH="$gregorio_dir/src:$PATH"

		mkdir output/texmf
		export output_texmf=$(realpath output/texmf)

		if ! (cd "$gregorio_dir" && TEXHASH="texhash $output_texmf" ./install-gtex.sh "dir:$output_texmf")
		then
			echo "Unable to install GregorioTeX to $output_texmf" >&2
			exit 2
		fi

		TEXMF="$(kpsewhich --var-value TEXMF)"
		TEXMF="${TEXMF/{/{$output_texmf,}"
		export TEXMF

		echo
	fi

	if ! gregorio -F dump -S -s </dev/null 2>/dev/null | grep -q 'SCORE INFOS'
	then
		echo "Gregorio is not installed properly or is not statically linked" >&2
		echo "When building, use ./configure --enable-all-static" >&2
		exit 3
	fi

	echo "Gregorio = $(which gregorio)"
	echo "GregorioTeX = $(kpsewhich gregoriotex.tex)"
	echo

	processors=$(nproc 2>/dev/null || echo 1)
	overall_result=0
	cd output
	for group in ${groups}
	do
		if ! ${group}_find | filter | xargs -P $processors -n 1 -i bash -c "${group}_test"' "$@"' _ {} \;
		then
			overall_result=1
		fi
	done

	echo

	if [ ${overall_result} != 0 ]
	then
		echo "${C_BAD}SOMETHING FAILED${C_RESET}"
		exit 1
	fi

	echo "${C_GOOD}ALL PASS${C_RESET}"
    ;;
accept|view_*)
    cd output
    for group in ${groups}
    do
        # this silliness is so that the command gets the tty of this script
        IFS=$'\r\n' GLOBIGNORE='*' :; filenames=( $(${group}_find | filter) )
        if [ "${#filenames[@]}" -gt 0 ]
        then
            for filename in "${filenames[@]}"
            do
                "${group}_$mode" "$filename"
            done
        fi
    done
    ;;
esac
exit 0
