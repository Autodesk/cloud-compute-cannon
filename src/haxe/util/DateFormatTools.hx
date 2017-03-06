package util;

import t9.abstracts.time.*;

using DateTools;
using StringTools;

class DateFormatTools
{
	public static function getMsFromString(s :String) :Milliseconds
	{
		if (s.endsWith('ms')) {
			return new Milliseconds(Std.parseFloat(s.replace('ms', '')));
		} else if (s.endsWith('h')) {
			var f = Std.parseFloat(s.replace('h', ''));
			return new Minutes(f*60).toMilliseconds();
		} else if (s.endsWith('s')) {
			return new Seconds(Std.parseFloat(s.replace('s', ''))).toMilliseconds();
		} else if (s.endsWith('m')) {
			return new Minutes(Std.parseFloat(s.replace('m', ''))).toMilliseconds();
		} else {
			return new Milliseconds(Std.parseFloat(s));
		}
	}
	public static function getShortStringOfDateDiff(d1 :Date, d2 :Date) :String
	{
		if (d1.getTime() < d2.getTime()) {
			var d3 = d1;
			d1 = d2;
			d2 = d3;
		}
		var dateBlob = DateTools.parse(d1.getTime() - d2.getTime());
		var date = Date.fromTime(d1.getTime() - d2.getTime());
		if (dateBlob.days > 0) {
			return '${dateBlob.days}d';
		} else if (dateBlob.hours > 0) {
			return '${dateBlob.hours}h';
		} else if (dateBlob.minutes > 0) {
			return '${dateBlob.minutes}m';
		} else {
			return '${dateBlob.seconds + (dateBlob.ms / 1000)}s';
		}
	}

	public static function getFormattedDate(time :Float, ?formatString:String, ?tz :String) :String
	{
		tz = tz == null ? "America/Los_Angeles" : tz;
		formatString = formatString == null ? "YYYY-MM-DDTHH:mm:ss z" : formatString;
		return new js.npm.moment.MomentTimezone(time).tz(tz).format(formatString).toString();
	}
}