/*
	MOMENT.CFC
	-------------------
	Inspired by (but not a strict port of) moment.js: http://momentjs.com/
	With help from: @seancorfield, @ryanguill
	And contributions (witting or otherwise) from:
	 - Dan Switzer: https://github.com/CounterMarch/moment.cfc/issues/5
	 - Ryan Heldt: http://www.ryanheldt.com/post.cfm/working-with-fuzzy-dates-and-times
	 - Ben Nadel: http://www.bennadel.com/blog/2501-converting-coldfusion-date-time-values-into-iso-8601-time-strings.htm
	 - Zack Pitts: http://stackoverflow.com/a/16309780/751
*/
component displayname="moment" {

	variables.zone = '';
	variables.time = '';
	variables.utcTime = '';

	/*
		Call:
			new moment();
				-- for instance initalized to current time in current system TZ
			new moment( someTimeValue );
				-- for instance initialized to someTimeValue in current system TZ
			new moment( someTimeValue, someTZID )
				-- for instance initialized to someTimeValue in someTZID TZ
	*/
	public function init( time = now(), zone = getSystemTZ() ) {
		variables.time = (time contains '{ts') ? time : parseDateTime( arguments.time );
		variables.zone = zone;
		variables.utcTime = TZtoUTC( arguments.time, arguments.zone );
		return this;
	}

	//===========================================
	//MUTATORS
	//===========================================

	public function utc() hint="convert datetime to utc zone" {
		variables.time = variables.utcTime;
		variables.zone = 'UTC';
		return this;
	}

	public function tz( required string zone ) hint="convert datetime to specified zone" {
		variables.time = UTCtoTZ( variables.utcTime, arguments.zone );
		variables.zone = arguments.zone;
		return this;
	}

	public function add( required numeric amount, required string part ){
		part = canonicalizeDatePart( part, 'dateAdd' );
		variables.time = dateAdd( part, amount, variables.time );
		variables.utcTime = TZtoUTC( variables.time, variables.zone );
		return this;
	}

	public function subtract( required numeric amount, required string part ){
		return add( -1 * amount, part );
	}

	//===========================================
	//STATICS
	//===========================================

	public moment function clone() hint="returns a new instance with the same time & zone" {
		return new moment( variables.time, variables.zone );
	}

	public moment function min( required moment a, required moment b ) hint="returns whichever moment came first" {
		if ( a.isBefore( b ) ){
			return a;
		}
		return b;
	}

	public moment function max( required moment a, required moment b ) hint="returns whichever moment came last" {
		if ( a.isAfter( b ) ){
			return a;
		}
		return b;
	}

	public numeric function diff( required moment b, part = 'seconds' ) hint="get the difference between the current date and the specified date" {
		part = canonicalizeDatePart( part, 'dateDiff' );
		if (part == 'L'){ //custom support for millisecond diffing... because adobe couldn't be bothered to support it themselves
			return b.epoch() - this.epoch();
		}
		return dateDiff( part, this.getDateTime(), b.getDateTime() );
	}

	public function getZoneCurrentOffset( required string zone ) hint="returns the offset in seconds (considering DST) of the specified zone" {
		return getTZ( arguments.zone ).getOffset( getSystemTimeMS() ) / 1000;
	}

	public string function getSystemTZ(){
		return createObject('java', 'java.util.TimeZone').getDefault().getId();
	}

	public struct function getZoneTable(){
		var list = createObject('java', 'java.util.TimeZone').getAvailableIDs();
		var data = {};
		for (tz in list){
			//display *CURRENT* offsets
			var ms = getTZ( tz ).getOffset( getSystemTimeMS() );
			data[ tz ] = readableOffset( ms );
		}
		return data;
	}

	public function getArbitraryTimeOffset( time, zone ) hint="returns what the offset was at that specific moment"{
		var timezone = getTZ( zone );
		//can't use a moment for this math b/c it would cause infinite recursion: constructor uses this method
		var epic = createDateTime(1970, 1, 1, 0, 0, 0);
		var seconds = timezone.getOffset( javacast('long', dateDiff('s', epic, arguments.time)*1000) ) / 1000;
		return seconds;
	}

	//===========================================
	//TERMINATORS
	//===========================================

	public function format( required string mask ) hint="return datetime formatted with specified mask (dateTimeFormat mask rules)" {
		switch( mask ){
			case 'mysql':
				mask = 'yyyy-mm-dd HH:nn:ss';
				break;
			case 'iso8061':
			case 'mssql':
				return dateTimeFormat(variables.time, 'yyyy-mm-dd') & 'T' & dateTimeFormat(variables.time, 'HH:nn:ss') & 'Z';
			default:
				mask = mask;
		}

		return dateTimeFormat( variables.time, mask );
	}

	public function from( required moment compare ) hint="returns fuzzy-date string e.g. 2 hours ago" {
		var _moment = new moment( variables.utcTime, 'UTC' );
		var L = this.min( _moment, compare.clone().utc() ).getDateTime();
		var R = this.max( _moment, compare.clone().utc() ).getDateTime();
		var diff = 0;
		//Seconds
		if (dateDiff('s', L, R) < 60){
			return 'Just now';
		}
		//Minutes
		diff = dateDiff('n', L, R);
		if (diff < 60){
			return diff & " minute#(diff gt 1 ? 's' : '')# ago";
		}
		//Hours
		diff = dateDiff('h', L, R);
		if (diff < 24){
			return diff & " hour#(diff gt 1 ? 's' : '')# ago";
		}
		//Days
		diff = dateDiff('d', L, R);
		if (diff < 7){
			return 'Last ' & dateTimeFormat(L, 'EEEE');
		}
		//Weeks
		diff = dateDiff('ww', L, R);
		if (diff == 1){
			return 'Last week';
		}else if (diff lt 4){
			return diff & ' weeks ago';
		}
		//Months/Years
		diff = dateDiff('m', L, R);
		if (diff < 12){
			return diff & " month#(diff gt 1 ? 's' : '')# ago";
		}else if (diff == 12){
			return 'Last year';
		}else{
			diff = dateDiff('yyyy', L, R);
			return diff & " year#(diff gt 1 ? 's' : '')# ago";
		}
	}

	public function fromNow() {
		var nnow = new moment().clone().utc().getDateTime();
		return from( nnow );
	}

	public function epoch() hint="returns the number of milliseconds since 1/1/1970 (local). Call .utc() first to get utc epoch" {
		return variables.time.getTime();
	}

	public function getDateTime() hint="return raw datetime object in current zone" {
		return variables.time;
	}

	public string function getZone() hint="return the current zone" {
		return variables.zone;
	}

	public numeric function getOffset() hint="returns the offset in seconds (considering DST) of the current moment" {
		return getArbitraryTimeOffset( variables.time, variables.zone );
	}

	//===========================================
	//QUERY
	//===========================================

	public boolean function isBefore( required moment compare, part = 'seconds' ) {
		part = canonicalizeDatePart( part, 'dateCompare' );
		return (dateCompare( variables.utcTime, compare.clone().utc().getDateTime(), part ) == -1);
	}

	public boolean function isSame( required moment compare, part = 'seconds' ) {
		part = canonicalizeDatePart( part, 'dateCompare' );
		return (dateCompare( variables.utcTime, compare.clone().utc().getDateTime(), part ) == 0);
	}

	public boolean function isAfter( required moment compare, part = 'seconds' ) {
		part = canonicalizeDatePart( part, 'dateCompare' );
		return (dateCompare( variables.utcTime, compare.clone().utc().getDateTime(), part ) == 1);
	}

	public boolean function isBetween( required moment a, required moment c, part = 'seconds' ) {
		part = canonicalizeDatePart( part, 'dateCompare' );
		return ( isBefore(c, part) && isAfter(a, part) );
	}

	public boolean function isDST() {
		var dt = createObject('java', 'java.util.Date').init( this.epoch() );
		return getTZ( variables.zone ).inDayLightTime( dt );
	}

	//===========================================
	//INTERNAL HELPERS
	//===========================================

	private function getSystemTimeMS(){
		return createObject('java', 'java.lang.System').currentTimeMillis();
	}

	private function getTZ( id ){
		return createObject('java', 'java.util.TimeZone').getTimezone( id );
	}

	private function TZtoUTC( time, tz = getSystemTZ() ){
		var seconds = getArbitraryTimeOffset( time, tz );
		return dateAdd( 's', -1 * seconds, time );
	}

	private function UTCtoTZ( required time, required string tz ){
		var seconds = getArbitraryTimeOffset( time, tz );
		return dateAdd( 's', seconds, time );
	}

	private function readableOffset( offset ){
		var h = offset / 1000 / 60 / 60; //raw hours (decimal) offset
		var hh = fix( h ); //int hours
		var mm = ( hh == h ? ':00' : ':' & abs(round((h-hh)*60)) ); //hours modulo used to determine minutes
		var rep = ( h >= 0 ? '+' : '' ) & hh & mm;
		return rep;
	}

	private function canonicalizeDatePart( part, method = 'dateAdd' ){
		var isDateAdd = (lcase(method) == 'dateadd');
		var isDateDiff = (lcase(method) == 'datediff');
		var isDateCompare = (lcase(method) == 'datecompare');

		switch( lcase(arguments.part) ){
			case 'years':
			case 'year':
			case 'y':
				return 'yyyy';
			case 'quarters':
			case 'quarter':
			case 'q':
				if (!isDateCompare) return 'q';
				throw(message='DateCompare doesn''t support Quarter precision');
			case 'months':
			case 'month':
			case 'm':
				return 'm';
			case 'weeks':
			case 'week':
			case 'w':
				if (!isDateCompare) return 'ww';
				throw(message='DateCompare doesn''t support Week precision');
			case 'days':
			case 'day':
			case 'd':
				return 'd';
			case 'weekdays':
			case 'weekday':
			case 'wd':
				if (!isDateCompare) return 'w';
				throw(message='DateCompare doesn''t support Weekday precision');
			case 'hours':
			case 'hour':
			case 'h':
				return 'h';
			case 'minutes':
			case 'minute':
			case 'n':
				return 'n';
			case 'seconds':
			case 'second':
			case 's':
				return 's';
			case 'milliseconds':
			case 'millisecond':
			case 'ms':
				if (isDateAdd) return 'L';
				if (isDateDiff) return 'L'; //custom support for ms diffing is provided interally, because adobe sucks
				throw(message='#method# doesn''t support Millisecond precision');
		}
		throw(message='Unrecognized Date Part: `#part#`');
	}

}
