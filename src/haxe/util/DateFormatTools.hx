package util;

using DateTools;

class DateFormatTools
{
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
			return '${dateBlob.seconds}s';
		}
	}
}