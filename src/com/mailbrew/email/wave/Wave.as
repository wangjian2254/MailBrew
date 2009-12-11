package com.mailbrew.email.wave
{
	import com.adobe.serialization.json.JSON;
	import com.mailbrew.email.EmailCounts;
	import com.mailbrew.email.EmailEvent;
	import com.mailbrew.email.EmailHeader;
	import com.mailbrew.email.EmailModes;
	import com.mailbrew.email.IEmailService;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.HTTPStatusEvent;
	import flash.events.IOErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.net.URLVariables;

	[Event(name="connectionFailed",        type="com.mailbrew.email.EmailEvent")]
	[Event(name="connectionSucceeded",     type="com.mailbrew.email.EmailEvent")]
	[Event(name="authenticationFailed",    type="com.mailbrew.email.EmailEvent")]
	[Event(name="authenticationSucceeded", type="com.mailbrew.email.EmailEvent")]
	[Event(name="unseenEmailsCount",       type="com.mailbrew.email.EmailEvent")]
	[Event(name="unseenEmails",            type="com.mailbrew.email.EmailEvent")]
	[Event(name="protocolError",           type="com.mailbrew.email.EmailEvent")]

	public class Wave extends EventDispatcher implements IEmailService
	{
		private const APP_NAME:String = "MailBrew";
		private const INBOX_URL:String = "https://wave.google.com/wave/";
		private const LOGIN_URL:String = "https://www.google.com/accounts/ClientLogin";
		private const LOGOUT_URL:String = "https://wave.google.com/wave/logout";
		private const INBOX_RE:RegExp = new RegExp(/var json = (\{"r":"\^d1".*});/);
		private const FROM_MAX:uint = 3;

		private var username:String;
		private var password:String;
		private var mode:String;
		private var internalMode:String;
		private var status:Number;
		private var authToken:String;

		public function Wave(username:String, password:String)
		{
			this.username = username;
			this.password = password;
		}
		
		private function login():void
		{
			this.status = NaN;
			this.internalMode = InternalModes.LOGIN;
			var urlLoader:URLLoader = new URLLoader();
			urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onIOError);
			urlLoader.addEventListener(Event.COMPLETE, onComplete);
			urlLoader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, onResponseStatus);
			var req:URLRequest = new URLRequest(LOGIN_URL);
			req.method = URLRequestMethod.POST;
			req.contentType = "application/x-www-form-urlencoded";
			var urlVars:URLVariables = new URLVariables();
			urlVars.accountType = "GOOGLE";
			urlVars.service = "wave";
			urlVars.source = APP_NAME;
			urlVars.Email = this.username;
			urlVars.Passwd = this.password;
			req.data = urlVars;
			urlLoader.load(req);
		}
		
		private function getInbox():void
		{
			this.status = NaN;
			this.internalMode = InternalModes.INBOX;
			var urlLoader:URLLoader = new URLLoader();
			urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onIOError);
			urlLoader.addEventListener(Event.COMPLETE, onComplete);
			urlLoader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, onResponseStatus);
			var req:URLRequest = new URLRequest(INBOX_URL);
			req.method = URLRequestMethod.GET;
			var urlVars:URLVariables = new URLVariables();
			urlVars.nouacheck = "";
			urlVars.auth = this.authToken;
			req.data = urlVars;
			urlLoader.load(req);
		}
		
		private function logout():void
		{
			this.status = NaN;
			this.internalMode = InternalModes.LOGOUT;
			var urlLoader:URLLoader = new URLLoader();
			urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onIOError);
			urlLoader.addEventListener(Event.COMPLETE, onComplete);
			urlLoader.addEventListener(HTTPStatusEvent.HTTP_RESPONSE_STATUS, onResponseStatus);
			var req:URLRequest = new URLRequest(LOGOUT_URL);
			req.method = URLRequestMethod.GET;
			var urlVars:URLVariables = new URLVariables();
			urlVars.auth = this.authToken;
			req.data = urlVars;
			urlLoader.load(req);
		}
		
		private function onResponseStatus(e:HTTPStatusEvent):void
		{
			this.status = e.status;
		}
		
		private function onIOError(e:IOErrorEvent):void
		{
			var ee:EmailEvent = new EmailEvent(EmailEvent.CONNECTION_FAILED);
			ee.data = e.text;
			this.dispatchEvent(ee);
		}
		
		private function onComplete(e:Event):void
		{
			if (this.status == 403)
			{
				var authFailedEvent:EmailEvent = new EmailEvent(EmailEvent.AUTHENTICATION_FAILED);
				this.dispatchEvent(authFailedEvent);
				return;
			}
			if (this.status != 200)
			{
				this.dispatchProtocolError("Unexpected response code: [" + this.status + "]");
				return;
			}
			this.dispatchEvent(new EmailEvent(EmailEvent.CONNECTION_SUCCEEDED));
			var urlLoader:URLLoader = e.target as URLLoader;
			var response:String = urlLoader.data as String;
			if (this.internalMode == InternalModes.LOGIN)
			{
				var responseStrings:Array = response.split("\n");
				var responseObj:Object = new Object();
				for each (var responseString:String in responseStrings)
				{
					var name:String = responseString.substring(0, responseString.indexOf("="));
					var value:String = responseString.substring(responseString.indexOf("=") + 1, responseString.length);
					if (name.length > 0 && value.length > 0)
					{
						responseObj[name] = value;
					}
				}
				if (responseObj["Error"] != null)
				{
					var authFailedEvent2:EmailEvent = new EmailEvent(EmailEvent.AUTHENTICATION_FAILED);
					authFailedEvent2.data = response.substring(response.indexOf("=") + 1, response.indexOf("\n"));
					this.dispatchEvent(authFailedEvent2);
				}
				else if (responseObj["Auth"] != null)
				{
					var authSucceededEvent:EmailEvent = new EmailEvent(EmailEvent.AUTHENTICATION_SUCCEEDED);
					authSucceededEvent.data = responseObj["Auth"];
					this.authToken = authSucceededEvent.data;
					this.dispatchEvent(authSucceededEvent);
					if (this.mode != EmailModes.AUTHENTICATION_TEST_MODE)
					{
						this.getInbox();
					}
				}
				else
				{
					this.dispatchProtocolError("Login attempt failed. Request returned an unexpected response: [" + response + "]");
					return;
				}
			}
			else if (this.internalMode == InternalModes.INBOX)
			{
				try
				{
					var inboxString:String = INBOX_RE.exec(response)[1];
					var inboxObj:Object = JSON.decode(inboxString, true);
					var p:Object = inboxObj.p;
					var inbox:Array = p[1]; // This is the entire inbox -- everything you see when you log into Wave
					var messageTotal:Number = 0;
					var unreadTotal:Number = 0;
					var emailHeaders:Vector.<EmailHeader> = new Vector.<EmailHeader>();
					for each (var thread:Object in inbox)
					{
						var i:uint;
						var unread:Number = thread[7];
						messageTotal += thread[6];
						unreadTotal += unread;
						if (unread == 0) continue;
						var emailHeader:EmailHeader = new EmailHeader();
						emailHeader.id = thread[1];
						emailHeader.url = "https://wave.google.com/wave/#restored:wave:" + encodeURIComponent(encodeURIComponent(emailHeader.id)); // Must be encoded twice.
						var fromInformation:Array = thread[5];
						var fromString:String = new String();
						for (i = 0; i < fromInformation.length; ++i)
						{
							var fromStrTmp:String = fromInformation[i];
							fromString += fromStrTmp.substring(0, fromStrTmp.indexOf("@"));
							if (i == FROM_MAX - 1)
							{
								if (fromInformation.length > FROM_MAX)
								{
									fromString += "...";
								}
								break;
							}
							if (i != fromInformation.length - 1) fromString += ", ";
						}
						emailHeader.from = fromString;
						emailHeader.subject = thread[9][1];
						var summaryInformation:Array = thread[10];
						var summary:String = new String();
						for (i = 0; i < summaryInformation.length; ++i)
						{
							summary += summaryInformation[i][1];
							if (i == FROM_MAX - 1)
							{
								if (summaryInformation.length > FROM_MAX)
								{
									summary += "...";
								}
								break;
							}
							if (i != summaryInformation.length - 1) summary += "...";
						}
						emailHeader.summary = summary;
						emailHeaders.push(emailHeader);
					}
				}
				catch (error:Error)
				{
					this.dispatchProtocolError("Error parsing inbox. Google might have changed something. Expect an update soon. [" +error.message+ "]");
					return;
				}
				if (this.mode == EmailModes.UNSEEN_COUNT_MODE)
				{
					var emailCounts:EmailCounts = new EmailCounts();
					emailCounts.totalEmails = messageTotal;
					emailCounts.unseenEmails = unreadTotal;
					var unseenCountEvent:EmailEvent = new EmailEvent(EmailEvent.UNSEEN_EMAILS_COUNT);
					unseenCountEvent.data = emailCounts;
					this.dispatchEvent(unseenCountEvent);
				}
				else if (this.mode == EmailModes.UNSEEN_EMAIL_HEADERS_MODE)
				{
					var unseenEmailEvent:EmailEvent = new EmailEvent(EmailEvent.UNSEEN_EMAILS);
					unseenEmailEvent.data = emailHeaders;
					this.dispatchEvent(unseenEmailEvent);
				}
				// Logging out logs out the browser client, as well.
				// Best to skip it until we have real API support.
				//this.logout();
			}
			else if (this.internalMode == InternalModes.LOGOUT)
			{
				// Not much to do. Bye.
			}
		}
		
		private function dispatchProtocolError(msg:String):void
		{
			var pe:EmailEvent = new EmailEvent(EmailEvent.PROTOCOL_ERROR);
			pe.data = msg;
			this.dispatchEvent(pe);
		}
		
		public function testAccount():void
		{
			this.mode = EmailModes.AUTHENTICATION_TEST_MODE;
			this.login();
		}

		public function getUnseenEmailCount():void
		{
			this.mode = EmailModes.UNSEEN_COUNT_MODE;
			this.login();
		}
		
		public function getUnseenEmailHeaders():void
		{
			this.mode = EmailModes.UNSEEN_EMAIL_HEADERS_MODE;
			this.login();
		}
	}
}