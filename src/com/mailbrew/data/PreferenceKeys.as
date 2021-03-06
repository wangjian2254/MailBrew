package com.mailbrew.data
{
	public class PreferenceKeys
	{
		public static const UPDATE_INTERVAL:String                     = "updateInterval";
		public static const UPDATE_INTERVAL_DEFAULT:uint               = 5;

		public static const NOTIFICATION_DISPLAY_INTERVAL:String       = "notificationDisplayInterval";
		public static const NOTIFICATION_DISPLAY_INTERVAL_DEFAULT:uint = 7;
		
		public static const IDLE_THRESHOLD:String                      = "idleThreshold";
		public static const IDLE_THRESHOLD_DEFAULT:uint                = 10;
		
		public static const APPLICATION_ALERT:String                   = "applicationAlert";
		public static const APPLICATION_ALERT_DEFAULT:Boolean          = false;

		public static const COLLECT_USAGE_DATA:String                  = "collectUsageData";
		public static const COLLECT_USAGE_DATA_DEFAULT:Boolean         = false;
		public static const COLLECT_USAGE_DATA_PROMPT:String           = "collectUsageDataPrompt";
		
		public static const START_AT_LOGIN_DEFAULT:Boolean             = false;

		public static const SUMMARY_WINDOW_POINT:String                = "summaryWindowPoint";
		
		public static const DATABASE_PASSWORD:String                   = "databasePassword";
		
		public static const MAILBREW_INSTALLATION_FLAG:String          = "mailbrewInstallationFlag";
		public static const MONTHLY_REPORT_TIMESTAMP:String            = "monthlyReportTimestamp";
	}
}