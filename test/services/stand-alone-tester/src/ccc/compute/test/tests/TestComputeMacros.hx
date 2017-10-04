package ccc.compute.test.tests;

import co.janicek.core.math.UUID;

import haxe.macro.Context;
import haxe.macro.MacroStringTools;

class TestComputeMacros
{
	public static macro function buildTestContent(TESTNAME :String)
	{
		var ShortId = {
			generate: function() :String {
				return UUID.uuid(8);
			}
		}
		var TEST_BASE = 'tests';
		trace('here');
		var pos = haxe.macro.Context.currentPos();
		var random = '${ShortId.generate()}';
		return macro @:mergeBlock {
			var inputValueInline = MacroStringTools.formatString('in${ShortId.generate()}', pos);
			var inputName2 = 'in${ShortId.generate()}';
			var inputName3 = 'in${ShortId.generate()}';

			var outputName1 = 'out${ShortId.generate()}';
			var outputName2 = 'out${ShortId.generate()}';
			var outputName3 = 'out${ShortId.generate()}';

			var outputValue1 = 'out${ShortId.generate()}';

			var inputInline :ComputeInputSource = {
				type: InputSource.InputInline,
				value: inputValueInline,
				name: inputName2
			}

			var inputUrl :ComputeInputSource = {
				type: InputSource.InputUrl,
				value: 'https://www.google.com/textinputassistant/tia.png',
				name: inputName3
			}

			var customInputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_INPUTS';
			var customOutputsPath = '$TEST_BASE/$TESTNAME/$random/$DIRECTORY_OUTPUTS';
			var customResultsPath = '$TEST_BASE/$TESTNAME/$random/results';

			var outputValueStdout = MacroStringTools.formatString('out${ShortId.generate()}');
			var outputValueStderr = 'out${ShortId.generate()}';
			//Multiline stdout
			var script = MacroStringTools.formatString(
'#!/bin/sh
echo "$outputValueStdout"
echo "$outputValueStdout"
echo foo
echo "$outputValueStdout"
echo "$outputValueStderr" >> /dev/stderr
echo "$outputValue1" > /$DIRECTORY_OUTPUTS/$outputName1
cat /$DIRECTORY_INPUTS/$inputName2 > /$DIRECTORY_OUTPUTS/$outputName2
cat /$DIRECTORY_INPUTS/$inputName3 > /$DIRECTORY_OUTPUTS/$outputName3
	');
			var targetStdout = '$outputValueStdout\n$outputValueStdout\nfoo\n$outputValueStdout'.trim();
			var targetStderr = '$outputValueStderr';
			var scriptName = 'script.sh';
			var inputScript :ComputeInputSource = {
				type: InputSource.InputInline,
				value: script,
				name: scriptName
			}

			var inputsArray = [inputInline, inputUrl, inputScript];
		};
	}
}