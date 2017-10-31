package ccc;
/**
 * This enumerates all the possible error conditions that will return
 * a 400 status code on job requests or results requests.
 */
@:enum
abstract JobSubmissionError(String) to String from String {
	var Docker_Image_Unknown = 'Docker_Image_Unknown';
}