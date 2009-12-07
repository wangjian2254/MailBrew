package com.mailbrew.commands
{
	import com.adobe.air.crypto.EncryptionKeyGenerator;
	import com.adobe.air.notification.Purr;
	import com.adobe.air.preferences.Preference;
	import com.adobe.cairngorm.commands.ICommand;
	import com.adobe.cairngorm.control.CairngormEvent;
	import com.mailbrew.data.PreferenceKeys;
	import com.mailbrew.database.Database;
	import com.mailbrew.database.DatabaseEvent;
	import com.mailbrew.database.DatabaseResponder;
	import com.mailbrew.events.CheckMailEvent;
	import com.mailbrew.events.PopulateAccountListEvent;
	import com.mailbrew.model.ModelLocator;
	
	import flash.desktop.NativeApplication;
	import flash.events.Event;
	import flash.events.TimerEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.utils.ByteArray;
	import flash.utils.Timer;
	
	public class InitCommand
		implements ICommand
	{
		private var ml:ModelLocator;
		
		public function execute(e:CairngormEvent):void
		{
			this.ml = ModelLocator.getInstance();
			
			this.ml.prefs = new Preference();
			this.ml.prefs.load();
			
			// Set up preferences...
			var defaultsSet:Boolean = false;
			if (this.ml.prefs.getValue(PreferenceKeys.UPDATE_INTERVAL) == null)
			{
				this.ml.prefs.setValue(PreferenceKeys.UPDATE_INTERVAL, 5, false);
				defaultsSet = true;
			}

			if (this.ml.prefs.getValue(PreferenceKeys.NOTIFICATION_DISPLAY_INTERVAL) == null)
			{
				this.ml.prefs.setValue(PreferenceKeys.NOTIFICATION_DISPLAY_INTERVAL, 7, false);
				defaultsSet = true;
			}

			if (this.ml.prefs.getValue(PreferenceKeys.IDLE_THRESHOLD) == null)
			{
				this.ml.prefs.setValue(PreferenceKeys.IDLE_THRESHOLD, 10, false);
				defaultsSet = true;
			}
			
			if (defaultsSet) this.ml.prefs.save();
			
			this.ml.purr = new Purr(this.ml.prefs.getValue(PreferenceKeys.IDLE_THRESHOLD));
			
			this.ml.notificationIcon = new this.ml.NotificationIconClass();
			
			var databasePassword:String = this.ml.prefs.getValue("databasePassword");
			if (databasePassword == null)
			{
				databasePassword = this.generateStrongPassword();
				this.ml.prefs.setValue("databasePassword", databasePassword, true);
				this.ml.prefs.save();
			}
			var sqlFile:File = File.applicationDirectory.resolvePath("sql.xml");
			var sqlFileStream:FileStream = new FileStream();
			sqlFileStream.open(sqlFile, FileMode.READ);
			var sql:XML = new XML(sqlFileStream.readUTFBytes(sqlFileStream.bytesAvailable));
			sqlFileStream.close();
			var keyGenerator:EncryptionKeyGenerator = new EncryptionKeyGenerator();
			var encryptionKey:ByteArray = keyGenerator.getEncryptionKey(databasePassword);
			var db:Database = new Database(sql, encryptionKey);
			var responder:DatabaseResponder = new DatabaseResponder();
			var resultListener:Function = function(e:DatabaseEvent):void
			{
				responder.removeEventListener(DatabaseEvent.RESULT_EVENT, resultListener);
				ml.db = db;
				createAccountsTable();
			};
			responder.addEventListener(DatabaseEvent.RESULT_EVENT, resultListener);
			db.initialize(responder);
		}
		
		private function createAccountsTable():void
		{
			var responder:DatabaseResponder = new DatabaseResponder();
			responder.addEventListener(DatabaseEvent.RESULT_EVENT, createMessagesTable);
			ModelLocator.getInstance().db.createAccountsTable(responder);			
		}
		
		private function createMessagesTable(e:Event):void
		{
			var oldResponder:DatabaseResponder = e.target as DatabaseResponder;
			oldResponder.removeEventListener(DatabaseEvent.RESULT_EVENT, createMessagesTable);
			var responder:DatabaseResponder = new DatabaseResponder();
			responder.addEventListener(DatabaseEvent.RESULT_EVENT, start);
			ModelLocator.getInstance().db.createMessagesTable(responder);			
		}
		
		private function start(e:Event):void
		{
			var oldResponder:DatabaseResponder = e.target as DatabaseResponder;
			oldResponder.removeEventListener(DatabaseEvent.RESULT_EVENT, start);
			new PopulateAccountListEvent().dispatch();
			this.ml.checkEmailTimer = new Timer(this.ml.prefs.getValue(PreferenceKeys.UPDATE_INTERVAL) * 60 * 1000);
			this.ml.checkEmailTimer.addEventListener(TimerEvent.TIMER, ml.checkEmail);
			this.ml.checkEmailTimer.start();
			// TBD: Add this back in
			//new CheckMailEvent().dispatch();
		}
		
		private static const POSSIBLE_CHARS:Array = ["abcdefghijklmnopqrstuvwxyz","ABCDEFGHIJKLMNOPQRSTUVWXYZ","0123456789","~`!@#$%^&*()_-+=[{]}|;:'\"\\,<.>/?"];
		
		private function generateStrongPassword(length:uint = 32):String
		{
			if (length < 8) length = 8;
			var pw:String = new String;
			var charPos:uint = 0;
			while (pw.length < length)
			{
				var chars:String = POSSIBLE_CHARS[charPos];
				var char:String = chars.charAt(this.getRandomWholeNumber(0, chars.length - 1));
				var splitPos:uint = this.getRandomWholeNumber(0, pw.length);
				pw = (pw.substring(0, splitPos) + char + pw.substring(splitPos, pw.length));
				charPos = (charPos == 3) ? 0 : charPos + 1;
			}
			return pw;
		}
		
		private function getRandomWholeNumber(min:Number, max:Number):Number
		{
			return Math.round(((Math.random() * (max - min)) + min));
		}
	}
}
