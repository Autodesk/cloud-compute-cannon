#Loads input files and dumps to similarly named output files
from __future__ import print_function
import sys
import os, os.path, json
import codecs

print('Starting python in container!')

if os.path.exists('/inputs'):
	print('/inputs', os.listdir('/inputs'))
	for f in os.listdir('/inputs'):
		try:
			fileName = os.path.join('/inputs', f)
			print('fileName', fileName)
			fp = codecs.open(fileName, "r", "utf-8")
			text = fp.read()
			outfile = '/outputs/' + f + '_out'
			with open(outfile, 'w') as outfile:
				outfile.write(text + '_OUT')
		except RuntimeError as e:
			print("ERROR: ", e, file=sys.stderr)

else:
	print('No folder=/inputs')

print('THIS IS STDOUT')
print("THIS IS STDERR", file=sys.stderr)
