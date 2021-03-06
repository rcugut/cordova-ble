/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import "BLE.h"

//////////////////////////////////////////////////////////////////
//                  Class Extension CBUUID                      //
//////////////////////////////////////////////////////////////////

@interface CBUUID (StringExtraction)

- (NSString *) uuidString;

@end

@implementation CBUUID (StringExtraction)

/**
 * Get the UUID formatted as a string. This method takes into
 * consideration the use of the Bluetooth Base UUID, see:
 *   Bluetooth Core specification Version 4, Volume 3, Part B, Section 2.5.1
 *   Bluetooth Core specification Version 4, Volume 3, Part F, Section 3.2.1
 * For example, the 2-byte UUID:
 *   1800
 * becomes this 16-byte UUID when using the Base UUID:
 *   00001800-0000-1000-8000-00805f9b34fb
 */
- (NSString *) uuidString
{
	NSData* data = [self data];

	NSUInteger uuidNumBytes = [data length];
	const unsigned char* uuidBytes = [data bytes];

	NSMutableString* outputString = [NSMutableString stringWithCapacity: 16];

	if (2 == uuidNumBytes)
	{
		// Apply the Bluetooth Base UUID to 2-byte UUID:
		[outputString
			appendFormat: @"0000%02x%02x-0000-1000-8000-00805f9b34fb",
			uuidBytes[0], uuidBytes[1]];
	}
	else if (16 == uuidNumBytes)
	{
		// Format full 16-byte UUID.
		[outputString
			appendFormat: @"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
			uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
			uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
			uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
			uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]];
	}
	else
	{
		return nil; // Error.
	}

	return outputString;
}

@end

//////////////////////////////////////////////////////////////////
//               Class Extension CBPeripheral                   //
//////////////////////////////////////////////////////////////////

static int MyPerhiperalAssociatedObjectKey = 42;

@interface CBPeripheral (BLEPluginSupport)

- (void) setMyPerhiperal: (MyPeripheral*)myPeripheral;
- (MyPeripheral*) getMyPerhiperal;

@end

@implementation CBPeripheral (BLEPluginSupport)

- (void) setMyPerhiperal: (MyPeripheral*)myPeripheral
{
	objc_setAssociatedObject(
		self,
		&MyPerhiperalAssociatedObjectKey,
		myPeripheral,
		OBJC_ASSOCIATION_ASSIGN);
}

- (MyPeripheral*) getMyPerhiperal
{
	return objc_getAssociatedObject(
		self,
		&MyPerhiperalAssociatedObjectKey);
}

@end

//////////////////////////////////////////////////////////////////
//                      Class MyQueue                           //
//////////////////////////////////////////////////////////////////

@implementation MyQueue

- (MyQueue*) init
{
	self.array = [NSMutableArray array];
	return self;
}

- (void) enqueue: (id)item
{
	[self.array addObject: item];
}

- (id) dequeue
{
	id item = nil;
	if ([self.array count] != 0)
	{
		item = [self.array objectAtIndex: 0];
		[self.array removeObjectAtIndex: 0];
	}
	return item;
}

- (id) first
{
	id item = nil;
	if ([self.array count] != 0)
	{
		item = [self.array objectAtIndex: 0];
	}
	return item;
}

- (BOOL) isEmpty
{
	return 0 == [self.array count];
}

@end

//////////////////////////////////////////////////////////////////
//                     Class MyCommand                          //
//////////////////////////////////////////////////////////////////

@implementation MyCommand

- (MyCommand*) init
{
	return self;
}

- (void) doBlock
{
	(self.block)();
}

@end

//////////////////////////////////////////////////////////////////
//                   Class MyCallbackInfo                       //
//////////////////////////////////////////////////////////////////

@implementation MyCallbackInfo
@end

//////////////////////////////////////////////////////////////////
//                     Class MyPeriperal                        //
//////////////////////////////////////////////////////////////////

@implementation MyPeripheral

/****************************************************************/
/*                       Class Methods                          */
/****************************************************************/

+ (MyPeripheral*) withBLE: (BLE*) ble
	periperal: (CBPeripheral*) peripheral
{
	// Create instance.
	MyPeripheral* my = [MyPeripheral new];

	// Set handle and connect with associated objects.
	my.handle = [ble nextHandle];
	my.ble = ble;
	my.peripheral = peripheral;
	peripheral.delegate = my;
	[peripheral setMyPerhiperal: my];

	// Store in central dictionary.
	[ble.peripherals
		setObject: my
		forKey: my.handle];

	return my;
}

/****************************************************************/
/*                      Instance Methods                        */
/****************************************************************/

- (MyPeripheral*) init
{
	self.objects = [NSMutableDictionary dictionary];
	self.commands = [MyQueue new];
	self.characteristicsCallbacks = [NSMutableDictionary dictionary];
	return self;
}

- (void) addObject: (id)obj withHandle: (id)handle
{
	self.objects[handle] = obj;
}

- (id) getObjectWithHandle: (id)handle
{
	return self.objects[handle];
}

- (void) removeObjectWithHandle: (id)handle
{
	[self.objects removeObjectForKey: handle];
}

- (void) addCommandForCallbackId: (NSString*)callbackId
	forObject: (id)obj
	operation: (int)type
	withBlock: (MyCommandBlock)block
{
	// Create command object.
	MyCommand* command = [MyCommand new];
	command.callbackId = callbackId;
	command.obj = obj;
	command.type = type;
	command.block = block;

	// If command queue is empty start the command now.
	BOOL startNow = [self.commands isEmpty];
	[self.commands enqueue: command];
	if (startNow)
	{
		[command doBlock];
	}
}

- (NSString*) getActiveCallbackId
{
	MyCommand* command = [self.commands first];
	return command.callbackId;
}

- (void) clearActiveCommandAndContinue
{
	// Remove the active command.
	[self.commands dequeue];

	// If there is a next command start it.
	if (![self.commands isEmpty])
	{
		MyCommand* command = [self.commands first];
		[command doBlock];
	}
}

- (void) assertCommandAvailable
{
	assert(![self.commands isEmpty]);
}

- (void) assertCommandHasObject: (id)obj andType: (int)type
{
	MyCommand* command = [self.commands first];
	assert(command.obj == obj);
	assert(command.type == type);
}

- (void) addCallbackForCharacteristic: (CBCharacteristic*)characteristic
	callbackId: (NSString*)callbackId
	isNotificationCallback: (BOOL) notify
{
	// Create callback info.
	MyCallbackInfo* callback = [MyCallbackInfo new];
	callback.callbackId = callbackId;
	callback.isNotificationCallback = notify;

	// Save callback for this characteristic. UUID is used as key.
	self.characteristicsCallbacks[characteristic.UUID] = callback;
}

// Note: Removes callback object if not notifying callback.
- (NSString*) getCallbackIdForCharacteristic: (CBCharacteristic*)characteristic
{
	MyCallbackInfo* callback = self.characteristicsCallbacks[characteristic.UUID];
	if (!callback.isNotificationCallback)
	{
		[self removeCallbackForCharacteristic: characteristic];
	}
	return callback.callbackId;
}

- (MyCallbackInfo*) getCallbackForCharacteristic: (CBCharacteristic*)characteristic
{
	return self.characteristicsCallbacks[characteristic.UUID];
}

- (void) removeCallbackForCharacteristic: (CBCharacteristic*)characteristic
{
	[self.characteristicsCallbacks removeObjectForKey: characteristic.UUID];
}

- (id) getObjectFromCommand: (CDVInvokedUrlCommand*)command atIndex: (NSUInteger) index
{
	NSString* handle = [command.arguments objectAtIndex: index];
	if (nil == handle)
	{
		[self.ble
			sendErrorMessage: @"missing handle argument"
			forCallback: command.callbackId];
		return nil;
	}

	id obj = [self getObjectWithHandle: handle];
	if (nil == obj)
	{
		[self.ble
			sendErrorMessage: @"object for handle not found"
			forCallback: command.callbackId];
		return nil;
	}

	return obj;
}

- (NSDictionary*) createServiceObject: (CBService*)service
	withHandle: (NSNumber*)handle
{
	return @{
		@"handle" : handle,
		@"uuid" : [[service UUID] uuidString],
		@"type" : (service.isPrimary ?
			@0 : // SERVICE_TYPE_PRIMARY
			@1)  // SERVICE_TYPE_SECONDARY
	};
}

- (NSDictionary*) createCharacteristicObject: (CBCharacteristic*)characteristic
	withHandle: (NSNumber*)handle
{
/*
	CBCharacteristicPropertyBroadcast = 0x01,
	CBCharacteristicPropertyRead = 0x02,
	CBCharacteristicPropertyWriteWithoutResponse = 0x04,
	CBCharacteristicPropertyWrite = 0x08,
	CBCharacteristicPropertyNotify = 0x10,
	CBCharacteristicPropertyIndicate = 0x20,
	CBCharacteristicPropertyAuthenticatedSignedWrites = 0x40,
	CBCharacteristicPropertyExtendedProperties = 0x80,
	CBCharacteristicPropertyNotifyEncryptionRequired = 0x100,
	CBCharacteristicPropertyIndicateEncryptionRequired = 0x200,
*/
/*
	1: 'PERMISSION_READ'
	2: 'PERMISSION_READ_ENCRYPTED',
	4: 'PERMISSION_READ_ENCRYPTED_MITM',
	16: 'PERMISSION_WRITE',
	32: 'PERMISSION_WRITE_ENCRYPTED',
	64: 'PERMISSION_WRITE_ENCRYPTED_MITM',
	128: 'PERMISSION_WRITE_SIGNED',
	256: 'PERMISSION_WRITE_SIGNED_MITM',
*/
/*
	1: 'PROPERTY_BROADCAST',
	2: 'PROPERTY_READ',
	4: 'PROPERTY_WRITE_NO_RESPONSE',
	8: 'PROPERTY_WRITE',
	16: 'PROPERTY_NOTIFY',
	32: 'PROPERTY_INDICATE',
	64: 'PROPERTY_SIGNED_WRITE',
	128: 'PROPERTY_EXTENDED_PROPS',
*/
/*
	1: 'WRITE_TYPE_NO_RESPONSE',
	2: 'WRITE_TYPE_DEFAULT',
	4: 'WRITE_TYPE_SIGNED',
*/

	CBCharacteristicProperties cprop = characteristic.properties;

	// Permission values.
	// Note: Not all permission values can be mapped on iOS.
	int permissions = 0;
	if (CBCharacteristicPropertyRead & cprop)
		permissions |= 1; // PERMISSION_READ
	if (CBCharacteristicPropertyWrite & cprop)
		permissions |= 16; // PERMISSION_WRITE

	// Property values.
	int properties = 0;
	if (CBCharacteristicPropertyBroadcast & cprop)
		properties |= 1; // PROPERTY_BROADCAST
	if (CBCharacteristicPropertyRead & cprop)
		properties |= 2; // PROPERTY_READ
	if (CBCharacteristicPropertyWriteWithoutResponse & cprop)
		properties |= 4; // PROPERTY_WRITE_NO_RESPONSE
	if (CBCharacteristicPropertyWrite & cprop)
		properties |= 8; // PROPERTY_WRITE
	if (CBCharacteristicPropertyNotify & cprop)
		properties |= 16; // PROPERTY_NOTIFY
	if (CBCharacteristicPropertyIndicate & cprop)
		properties |= 32; // PROPERTY_INDICATE
	if (CBCharacteristicPropertyAuthenticatedSignedWrites & cprop)
		properties |= 64; // PROPERTY_SIGNED_WRITE
	if (CBCharacteristicPropertyExtendedProperties & cprop)
		properties |= 128; // PROPERTY_EXTENDED_PROPS

	// Set writeType.
	int writeType = 0;
	if (CBCharacteristicPropertyWriteWithoutResponse & cprop)
		writeType |= 1; // WRITE_TYPE_NO_RESPONSE
	if (CBCharacteristicPropertyAuthenticatedSignedWrites & cprop)
		writeType |= 4; // WRITE_TYPE_SIGNED
	if (0 == writeType)
		writeType = 2; // WRITE_TYPE_DEFAULT

	return @{
		@"handle" : handle,
		@"uuid" : [characteristic.UUID uuidString],
		@"permission" : [NSNumber numberWithInt: permissions],
		@"property" : [NSNumber numberWithInt: properties],
		@"writeType" : [NSNumber numberWithInt: writeType]
	};
}

- (NSDictionary*) createDescriptorObject: (CBDescriptor*)descriptor
	withHandle: (NSNumber*)handle
{
	// Note: Permissions for descriptors are not available on iOS.
	int permissions = 0;

	return @{
		@"handle" : handle,
		@"uuid" : [descriptor.UUID uuidString],
		@"permission" : [NSNumber numberWithInt: permissions]
	};
}

/****************************************************************/
/*               Implemented Interface Methods                  */
/****************************************************************/

/**
 * From interface CBPeripheralDelegate.
 * Called when RSSI value has been read from device.
 */
- (void) peripheralDidUpdateRSSI: (CBPeripheral *)peripheral
	error: (NSError *)error
{
	[self assertCommandAvailable];
	[self assertCommandHasObject: peripheral andType: OPERATION_RSSI];

	if (nil == error)
	{
		// Success. Send back data to JS.
		[self.ble
			sendInt: [peripheral.RSSI intValue]
			forCallback: [self getActiveCallbackId]
			keepCallback: NO];
	}
	else
	{
		[self.ble
			sendErrorMessage: [error localizedDescription]
			forCallback: [self getActiveCallbackId]];
	}

	[self clearActiveCommandAndContinue];
}

/**
 * From interface CBPeripheralDelegate.
 * Called when services have been read from device.
 */
- (void) peripheral: (CBPeripheral *)peripheral
	didDiscoverServices: (NSError *)error
{
	[self assertCommandAvailable];
	[self assertCommandHasObject: peripheral andType: OPERATION_SERVICES];

	if (nil == error)
	{
		// Create array with Service objects.
		NSMutableArray* array = [NSMutableArray array];
		for (CBService* service in peripheral.services)
		{
			id handle = [self.ble nextHandle];
			[self addObject: service withHandle: handle];
			[array addObject: [self
				createServiceObject: service
				withHandle: handle]];
		}

		// Send back data to JS.
		[self.ble
			sendArray: array
			forCallback: [self getActiveCallbackId]
			keepCallback: NO];
	}
	else
	{

		[self.ble
			sendErrorMessage: [error localizedDescription]
			forCallback: [self getActiveCallbackId]];
	}

	[self clearActiveCommandAndContinue];
}

- (void)peripheral: (CBPeripheral *)peripheral
	didDiscoverCharacteristicsForService: (CBService *)service
	error:(NSError *)error
{
	[self assertCommandAvailable];
	[self assertCommandHasObject: service andType: OPERATION_CHARACTERISTICS];

	if (nil == error)
	{
		// Create array with Service objects.
		NSMutableArray* array = [NSMutableArray array];
		for (CBCharacteristic* characteristic in service.characteristics)
		{
			id handle = [self.ble nextHandle];
			[self addObject: characteristic withHandle: handle];
			[array addObject: [self
				createCharacteristicObject: characteristic
				withHandle: handle]];
		}

		// Send back data to JS.
		[self.ble
			sendArray: array
			forCallback: [self getActiveCallbackId]
			keepCallback: NO];
	}
	else
	{
		// Rather than returning an error, we return an empty array of characteristics.
		NSMutableArray* array = [NSMutableArray array];
		[self.ble
			sendArray: array
			forCallback: [self getActiveCallbackId]
			keepCallback: NO];

		// Old code that returned an error.
		//[self.ble
		//	sendErrorMessage: [error localizedDescription]
		//	forCallback: [self getActiveCallbackId]];
	}

	[self clearActiveCommandAndContinue];
}

- (void)peripheral: (CBPeripheral *)peripheral
	didDiscoverDescriptorsForCharacteristic: (CBCharacteristic *)characteristic
	error: (NSError *)error
{
	[self assertCommandAvailable];
	[self assertCommandHasObject: characteristic andType: OPERATION_DESCRIPTORS];

	if (nil == error)
	{
		// Create array with Descriptor objects.
		NSMutableArray* array = [NSMutableArray array];
		for (CBDescriptor* descriptor in characteristic.descriptors)
		{
			id handle = [self.ble nextHandle];
			[self addObject: descriptor withHandle: handle];
			[array addObject: [self
				createDescriptorObject: descriptor
				withHandle: handle]];
		}

		// Send back data to JS.
		[self.ble
			sendArray: array
			forCallback: [self getActiveCallbackId]
			keepCallback: NO];
	}
	else
	{
		// Rather than returning an error, we return an empty array of descriptors.
		NSMutableArray* array = [NSMutableArray array];
		[self.ble
			sendArray: array
			forCallback: [self getActiveCallbackId]
			keepCallback: NO];

		// Old code that returned an error.
		//[self.ble
		//	sendErrorMessage: [error localizedDescription]
		//	forCallback: [self getActiveCallbackId]];
	}

	[self clearActiveCommandAndContinue];
}

// Note: Called both on read and notify!
- (void) peripheral: (CBPeripheral *)peripheral
	didUpdateValueForCharacteristic: (CBCharacteristic *)characteristic
	error: (NSError *)error
{
	MyCallbackInfo* callback = [self
		getCallbackForCharacteristic: characteristic];

	// Perhaps it might happen that the notification is disabled
	// and the callback removed, but there is still a pending
	// notification, that is sent after notification is disabled.
	// Here we check for this case.
	// This error should not cause any harm and should be safe to ignore.
	if (nil == callback)
	{
		// Print a log message so we can see if this ever happens.
		NSLog(@"BLE.m: Callback for characteristic not found: %@", characteristic);
		return; // Error
	}

	if (nil == error)
	{
		// Send back data to JS.
		NSData* buffer = characteristic.value;
		[self.ble
			sendBuffer: buffer
			forCallback: callback.callbackId
			keepCallback: callback.isNotificationCallback];
	}
	else
	{
		[self.ble
			sendErrorMessage: [error localizedDescription]
			forCallback: callback.callbackId];
	}
}

- (void)peripheral:(CBPeripheral *) peripheral
	didUpdateValueForDescriptor: (CBDescriptor *)descriptor
	error:(NSError *)error
{
	[self assertCommandAvailable];
	[self assertCommandHasObject: descriptor andType: OPERATION_READ_DESCRIPTOR];

	if (nil == error)
	{
		// A descriptors value can be of different types. Here we
		// convert the value to a buffer before sending it to JS.
		// TODO: What should be done with zero values?
		NSData* buffer = nil;
		if ([descriptor.value isKindOfClass: [NSNumber class]])
		{
			int integer = [descriptor.value intValue];
			buffer = [NSData dataWithBytes: &integer length: sizeof(integer)];
		}
		else if ([descriptor.value isKindOfClass: [NSString class]])
		{
			buffer = [descriptor.value dataUsingEncoding: NSUTF8StringEncoding];
		}
		else if ([descriptor.value isKindOfClass: [NSData class]])
		{
			buffer = descriptor.value;
		}
		else
		{
			// Not a known class type for descriptor.value.
			assert(false);
		}

		// Send back data to JS.
		[self.ble
			sendBuffer: buffer
			forCallback: [self getActiveCallbackId]
			keepCallback: NO];
	}
	else
	{
		[self.ble
			sendErrorMessage: [error localizedDescription]
			forCallback: [self getActiveCallbackId]];
	}

	[self clearActiveCommandAndContinue];
}

- (void) peripheral: (CBPeripheral *)peripheral
	didWriteValueForCharacteristic: (CBCharacteristic *)characteristic
	error:(NSError *)error
{
	[self assertCommandAvailable];
	[self assertCommandHasObject: characteristic andType: OPERATION_WRITE_CHARACTERISTIC];

	if (nil == error)
	{
		// Send success to JS.
		[self.ble sendOkClearCallback: [self getActiveCallbackId]];
	}
	else
	{
		[self.ble
			sendErrorMessage: [error localizedDescription]
			forCallback: [self getActiveCallbackId]];
	}

	[self clearActiveCommandAndContinue];
}

- (void) peripheral: (CBPeripheral *)peripheral
	didWriteValueForDescriptor: (CBDescriptor *)descriptor
	error: (NSError *)error
{
	[self assertCommandAvailable];
	[self assertCommandHasObject: descriptor andType: OPERATION_WRITE_DESCRIPTOR];

	if (nil == error)
	{
		// Send success to JS.
		[self.ble sendOkClearCallback: [self getActiveCallbackId]];
	}
	else
	{
		[self.ble
			sendErrorMessage: [error localizedDescription]
			forCallback: [self getActiveCallbackId]];
	}

	[self clearActiveCommandAndContinue];
}

@end

//////////////////////////////////////////////////////////////////
//                          Class BLE                           //
//////////////////////////////////////////////////////////////////

@implementation BLE

//////////////////////////////////////////////////////////////////
// TODO: Guard against parallel invocations of API calls.       //
// The API can only handle one scan, connect, etc call at once. //
//////////////////////////////////////////////////////////////////

/****************************************************************/
/*                   BLE plugin API Methods                     */
/****************************************************************/

/**
 * BLE API call: startScan
 */
- (void) startScan: (CDVInvokedUrlCommand*)command
{
	// Save callbackId.
	self.scanCallbackId = command.callbackId;

	// Start scanning.
	[self scanForPeripherals];
}

/**
 * BLE API call: stopScan
 */
- (void) stopScan: (CDVInvokedUrlCommand*)command
{
	if (self.central.state != CBCentralManagerStatePoweredOn)
	{
		self.scanIsWaiting = NO;
	}
	else
	{
		// Call native stopScan only if BLE is powered on.
		[self.central stopScan];

		if (self.scanCallbackId)
		{
			// Clear JS scan callback if scan is in progress.
			[self sendNoResultClearCallback: self.scanCallbackId];
			self.scanCallbackId = nil;
		}
	}
}

/**
 * BLE API call: connect
 */
- (void) connect: (CDVInvokedUrlCommand*)command
{
	// The connect address is in the first argument.
	NSString* address = [command.arguments objectAtIndex: 0];

	// Check that address was given.
	if (nil == address)
	{
		// Pass back error message.
		[self
			sendErrorMessage: @"no device address given"
			forCallback: command.callbackId];
		return;
	}

	// Get the pheripheral object for the given address.
	NSUUID* uuid = [[NSUUID UUID] initWithUUIDString: address];
	NSArray* pheriperals = [self.central
		retrievePeripheralsWithIdentifiers: @[uuid]];

	if ([pheriperals count] < 1)
	{
		// Pass back error message.
		[self
			sendErrorMessage: @"device with given address not found"
			forCallback: command.callbackId];
		return;
	}

	// Get first found pheriperal.
	CBPeripheral* peripheral = pheriperals[0];

	if (nil == peripheral)
	{
		// Pass back error message.
		[self
			sendErrorMessage: @"device not found"
			forCallback: command.callbackId];
		return;
	}

	// Check if periheral is already connected.
	if (nil != [peripheral getMyPerhiperal])
	{
		// Debug log.
		NSLog(@"BLE.m: Periheral was already connected");

		// Pass back error message.
		[self
			sendErrorMessage: @"device already connected"
			forCallback: command.callbackId];
	}
	else
	{
		// Not connected yet.

		// Create custom peripheral object.
		MyPeripheral* myPeripheral = [MyPeripheral
			withBLE: self
			periperal: peripheral];

		// Save Cordova callback id.
		myPeripheral.connectCallbackId = command.callbackId;

		// Send 'connecting' state to JS side.
		[self
			sendConnectionState: @1 // STATE_CONNECTING
			forMyPeriperhal: myPeripheral];

		// Connect. Result is given in methods:
		//   centralManager:didConnectPeripheral:
		//   centralManager:didDisconnectPeripheral:error:
		[self.central
			connectPeripheral: peripheral
			options: nil];
	}
}

/**
 * BLE API call: close
 */
- (void) close: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	// Disconnect the CBPeripheral.
	[self freePeripheral: myPeripheral.peripheral disconnect: YES];
}

/**
 * BLE API call: rssi
 */
- (void) rssi: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	// Read RSSI. Result is given in callback method:
	//   peripheralDidUpdateRSSI:error:
	CBPeripheral* __weak peripheral = myPeripheral.peripheral;
	[myPeripheral
		addCommandForCallbackId: command.callbackId
		forObject: peripheral
		operation: OPERATION_RSSI
		withBlock: ^{
			[peripheral readRSSI];
		}];
}

/**
 * BLE API call: services
 */
- (void) services: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	// Read services. Result is given in callback method:
	//   peripheral:didDiscoverServices:
	CBPeripheral* __weak peripheral = myPeripheral.peripheral;
	[myPeripheral
		addCommandForCallbackId: command.callbackId
		forObject: peripheral
		operation: OPERATION_SERVICES
		withBlock: ^{
			[peripheral discoverServices: nil];
		}];
}

- (void) characteristics: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBService* service = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == service) return; // Error.

	// Result is delivered in:
	//	peripheral:didDiscoverCharacteristicsForService:
	CBPeripheral* __weak peripheral = myPeripheral.peripheral;
	[myPeripheral
		addCommandForCallbackId: command.callbackId
		forObject: service
		operation: OPERATION_CHARACTERISTICS
		withBlock: ^{
			[peripheral
				discoverCharacteristics: nil
				forService: service];
			}];
}

- (void) descriptors: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBCharacteristic* characteristic = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == characteristic) return; // Error.

	// Result is delivered in:
	//	peripheral:didDiscoverCharacteristicsForService:
	CBPeripheral* __weak peripheral = myPeripheral.peripheral;
	[myPeripheral
		addCommandForCallbackId: command.callbackId
		forObject: characteristic
		operation: OPERATION_DESCRIPTORS
		withBlock: ^{
			[peripheral discoverDescriptorsForCharacteristic: characteristic];
		}];
}

- (void) readCharacteristic: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBCharacteristic* characteristic = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == characteristic) return; // Error.

	// Result is delivered in:
	//	peripheral:didUpdateValueForCharacteristic:error:
	// Note: This notification method is calledd both for read and notify.
	// Therefore the command queue cannot be used for read.
	[myPeripheral
		addCallbackForCharacteristic: characteristic
		callbackId: command.callbackId
		isNotificationCallback: NO];
	[myPeripheral.peripheral readValueForCharacteristic: characteristic];
}

- (void) readDescriptor: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBDescriptor* descriptor = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == descriptor) return; // Error.

	// Result is delivered in:
	//	peripheral:didUpdateValueForDescriptor:error:
	CBPeripheral* __weak peripheral = myPeripheral.peripheral;
	[myPeripheral
		addCommandForCallbackId: command.callbackId
		forObject: descriptor
		operation: OPERATION_READ_DESCRIPTOR
		withBlock: ^{
			[peripheral readValueForDescriptor: descriptor];
		}];
}

- (void) writeCharacteristic: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBCharacteristic* characteristic = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == characteristic) return; // Error.

	NSData* data = [command.arguments objectAtIndex: 2];
	if (nil == data)
	{
		[self
			sendErrorMessage: @"missing data argument"
			forCallback: command.callbackId];
		return;
	}

	// Determine allowed write type.
	//
	// Note: A characteristic can have both flags
	// CBCharacteristicWriteWithResponse and
	// CBCharacteristicWriteWithoutResponse set!
	// For example this is the case with RFduino.
	// It is important to check the value of writeType
	// below when determining if next command should
	// be executed at once.
	CBCharacteristicWriteType writeType;
	if (CBCharacteristicPropertyWrite & characteristic.properties)
	{
		writeType = CBCharacteristicWriteWithResponse;
	}
	else if (CBCharacteristicPropertyWriteWithoutResponse & characteristic.properties)
	{
		writeType = CBCharacteristicWriteWithoutResponse;
	}
	else
	{
		// Charateristic is not writeable.
		[self
			sendErrorMessage: @"write characteristic not permitted"
			forCallback: command.callbackId];
		return;
	}

	// Result for write type CBCharacteristicWriteWithResponse is delivered in:
	//	peripheral:didWriteValueForCharacteristic:error:
	CBPeripheral* __weak peripheral = myPeripheral.peripheral;
	[myPeripheral
		addCommandForCallbackId: command.callbackId
		forObject: characteristic
		operation: OPERATION_WRITE_CHARACTERISTIC
		withBlock: ^{
			[peripheral
				writeValue: data
				forCharacteristic: characteristic
				type: writeType];
		}];

	// If the write operation will not generate a response,
	// peripheral:didWriteValueForCharacteristic:error: will not
	// be called, and we need to run the next command now.
	//
	// Note: Important to check against writeType here since a
	// characteristic can have both these flags set:
	// CBCharacteristicWriteWithResponse
	// CBCharacteristicWriteWithoutResponse
	// Therefore you cannot check against those flags.
	if (writeType != CBCharacteristicWriteWithResponse)
	{
		// Run next command.
		[myPeripheral clearActiveCommandAndContinue];

		// Call success callback now since there will be no notification.
		[self sendOkClearCallback: command.callbackId];
	}
}

// Note: Writing the value of a Client Configuration Descriptor (UUID = 2902)
// does not work on iOS (application generates an exception). See this thread:
// http://stackoverflow.com/questions/13561136/corebluetooth-writevaluefordescriptor-issue
// In this case we do not write to the descriptor, see code below.
- (void) writeDescriptor: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBDescriptor* descriptor = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == descriptor) return; // Error.

	NSData* data = [command.arguments objectAtIndex: 2];
	if (nil == data)
	{
		[self
			sendErrorMessage: @"missing data argument"
			forCallback: command.callbackId];
		return;
	}

	// If UUID for descriptor is 2902 we should not write to the descriptor.
	// iOS will throw an NSInternalInconsistencyException exception in this case.
	NSData* uuidData = descriptor.UUID.data;
	NSUInteger uuidNumBytes = [uuidData length];
	const unsigned char* uuidBytes = [uuidData bytes];
	bool isUUID2902 = false;
	if (2 == uuidNumBytes)
	{
		isUUID2902 = ((0x29 == uuidBytes[0]) && (0x02 == uuidBytes[1]));
	}
	else if (16 == uuidNumBytes)
	{
		isUUID2902 = ((0x29 == uuidBytes[2]) && (0x02 == uuidBytes[3]));
	}

	if (isUUID2902)
	{
		// If the UUID is 2902 just send OK to JavaScript without
		// writing to the descriptor.
		[self sendOkClearCallback: command.callbackId];
	}
	else
	{
		// Result is delivered in:
		//	peripheral:didWriteValueForDescriptor:error:
		CBPeripheral* __weak peripheral = myPeripheral.peripheral;
		[myPeripheral
			addCommandForCallbackId: command.callbackId
			forObject: descriptor
			operation: OPERATION_WRITE_DESCRIPTOR
			withBlock: ^{
				[peripheral
					writeValue: data
					forDescriptor: descriptor];
			}];
	}
}

- (void) enableNotification: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBCharacteristic* characteristic = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == characteristic) return; // Error.

	// Result is delivered in:
	//	peripheral:didUpdateValueForCharacteristic:error:
	[myPeripheral
		addCallbackForCharacteristic: characteristic
		callbackId: command.callbackId
		isNotificationCallback: YES];
	[myPeripheral.peripheral
		setNotifyValue: YES
		forCharacteristic: characteristic];
}

- (void) disableNotification: (CDVInvokedUrlCommand*)command
{
	MyPeripheral* myPeripheral = [self getPeripheralFromCommand: command];
	if (nil == myPeripheral) return; // Error.

	CBCharacteristic* characteristic = [myPeripheral getObjectFromCommand: command atIndex: 1];
	if (nil == characteristic) return; // Error.

	// Turn off notification.
	[myPeripheral.peripheral
		setNotifyValue: NO
		forCharacteristic: characteristic];

	// Remove the callback from the JavaScript layer.
	MyCallbackInfo* callback = [myPeripheral
		getCallbackForCharacteristic: characteristic];
	[self sendNoResultClearCallback: callback.callbackId];

	// Remove the callback from the Objective-C layer.
	[myPeripheral removeCallbackForCharacteristic: characteristic];
}

- (void) reset: (CDVInvokedUrlCommand*)command
{
	// Disconnect and deallocate all connected peripherals.
	[self freePeripherals];

	// Just call the success callback for now.
	[self sendOkClearCallback: command.callbackId];
}

/****************************************************************/
/*               Implemented Interface Methods                  */
/****************************************************************/

/**
 * From interface CDVPlugin.
 * Called when plugin is initialized by Cordova.
 */
- (void) pluginInitialize
{
	self.scanIsWaiting = NO;

	self.central = [[CBCentralManager alloc]
		initWithDelegate: self
		queue: nil];

	self.peripherals = [NSMutableDictionary dictionary];

	self.handleCounter = 0;
}

/**
 * From interface CDVPlugin.
 * Called when the WebView navigates or refreshes.
 */
- (void) onReset
{
	[self freePeripherals];
}

/**
 * From interface CBCentralManagerDelegate.
 * Called when a device is discovered.
 */
- (void) centralManager: (CBCentralManager *)central
	didDiscoverPeripheral: (CBPeripheral *)peripheral
	advertisementData: (NSDictionary *)advertisementData
	RSSI: (NSNumber *)RSSI

{
	[self
		sendScanInfoForPeriperhal: peripheral
		RSSI: RSSI];
}

/**
 * From interface CBCentralManagerDelegate.
 * Called when the central manager changes state.
 */
- (void) centralManagerDidUpdateState: (CBCentralManager *)central
{
	// Start scan if we have a waiting scan that failed because
	// of the Central Manager not being on.
	if (central.state == CBCentralManagerStatePoweredOn
		&& self.scanIsWaiting)
	{
		[self scanForPeripherals];
	}
}

/**
 * From interface CBCentralManagerDelegate.
 * Called when a device is connected.
 */
- (void) centralManager: (CBCentralManager *)central
	didConnectPeripheral: (CBPeripheral *)peripheral
{
	[self
		sendConnectionState: @2 // STATE_CONNECTED
		forMyPeriperhal: [peripheral getMyPerhiperal]];
}

- (void)centralManager: (CBCentralManager *)central
	didFailToConnectPeripheral: (CBPeripheral *)peripheral
	error: (NSError *)error
{
	MyPeripheral* myPeripheral = [peripheral getMyPerhiperal];
	if (nil == myPeripheral) return;

	// Send connect failed to JS.
	[self
		sendErrorMessage: @"failed to connect"
		forCallback: myPeripheral.connectCallbackId];

	// Free allocated data. No need to disconnect,
	// since connection failed.
	[self freePeripheral: peripheral disconnect: NO];
}

/**
 * From interface CBCentralManagerDelegate.
 * Called when a device is disconnected.
 */
- (void) centralManager: (CBCentralManager *)central
	didDisconnectPeripheral: (CBPeripheral *)peripheral
	error: (NSError *)error
{
	MyPeripheral* myPeripheral = [peripheral getMyPerhiperal];
	if (nil == myPeripheral) return;

	// If the error object is non-nil the peripheral was
	// disconnected by the system (and not by close).
	// In this case, send STATE_DISCONNECTED to JS and
	// free peripheral data.
	if (nil != error)
	{
		// Send disconnected state to JS.
		[self
			sendConnectionState: @0 // STATE_DISCONNECTED
			forMyPeriperhal: myPeripheral];

		// Peripheral is already disconnected, but needs
		// to be deallocated.
		[self freePeripheral: peripheral disconnect: NO];
	}
}

/****************************************************************/
/*                      Instance Methods                        */
/****************************************************************/

/**
 * Free data associated with a periperal. Disconnect the
 * peripheral if the flag shouldDisconnect is true.
 */
- (void) freePeripheral: (CBPeripheral *)peripheral
	disconnect: (bool)shouldDisconnect
{
	MyPeripheral* myPeripheral = [peripheral getMyPerhiperal];
	if (nil == myPeripheral)
	{
		return;
	}

	// Clear connect callback on the JS side.
	[self sendNoResultClearCallback: myPeripheral.connectCallbackId];

	// Remove from dictionary.
	[self.peripherals removeObjectForKey: myPeripheral.handle];

	// Set references to nil.
	[peripheral setMyPerhiperal: nil];
	myPeripheral.peripheral = nil;
	myPeripheral.ble = nil;
	myPeripheral.connectCallbackId = nil;

	// Optionally disconnect the peripheral.
	if (shouldDisconnect)
	{
		[self.central cancelPeripheralConnection: peripheral];
	}
}

/**
 * Stop scanning, disconnect and deallocate all connected peripherals.
 */
- (void) freePeripherals
{
	// Stop scanning.
	[self.central stopScan];

	// Remove MyPeripheral and disconnect its associated peripheral.
	for (id key in self.peripherals)
	{
		MyPeripheral* myPeripheral = [self.peripherals objectForKey: key];
		[self freePeripheral: myPeripheral.peripheral disconnect: YES];
	}
}

/**
 * Increment and get the value of the handle counter.
 */
- (NSNumber*) nextHandle
{
	return [NSNumber numberWithInt: ++(self.handleCounter)];
}

/**
 * Internal helper method.
 */
- (int) scanForPeripherals
{
	if (self.central.state != CBCentralManagerStatePoweredOn)
	{
		// BLE is off, set flag that scan is waiting, scan will be restarted
		// in centralManagerDidUpdateState: when BLE is powered on.
		self.scanIsWaiting = YES;
		return -1;
	}

	self.scanIsWaiting = NO;

	NSDictionary* options = @{CBCentralManagerScanOptionAllowDuplicatesKey: @NO};

	[self.central
		scanForPeripheralsWithServices: nil
		options: options];

	return 0;
}

/**
 * Internal helper method.
 */
- (MyPeripheral*) getPeripheralFromCommand: (CDVInvokedUrlCommand*)command
{
	NSString* deviceHandle = [command.arguments objectAtIndex: 0];
	if (nil == deviceHandle)
	{
		[self
			sendErrorMessage: @"no device handle given"
			forCallback: command.callbackId];
		return nil;
	}

	MyPeripheral* myPeripheral = self.peripherals[deviceHandle];
	if (nil == myPeripheral)
	{
		[self
			sendErrorMessage: @"device not found"
			forCallback: command.callbackId];
		return nil;
	}

	return myPeripheral;
}

/**
 * Internal helper method.
 */
- (void) sendScanInfoForPeriperhal: (CBPeripheral *)peripheral
	RSSI: (NSNumber *)RSSI
{
	// Create an info object.
	// The UUID is used as the address of the device (the 6-byte BLE address
	// does not seem to be directly available on iOS).
	NSDictionary* info = @{
		@"address" : [peripheral.identifier UUIDString],
		@"rssi" : RSSI,
		@"name" : (peripheral.name != nil) ? peripheral.name : [NSNull null],
		@"scanRecord" : @""
	};

	// Send back data to JS.
	if (self.scanCallbackId)
	{
		[self
			sendDictionary: info
			forCallback: self.scanCallbackId
			keepCallback: YES];
	}
}

/**
 * Internal helper method.
 */
- (void) sendConnectionState: (NSNumber *)state
	forMyPeriperhal: (MyPeripheral *)myPeripheral
{
	// Create an info object.
	// The UUID is used as the address of the device (the 6-byte BLE address
	// does not seem to be directly available on iOS).
	NSDictionary* info = @{
		@"deviceHandle" : myPeripheral.handle,
		@"state" : state
	};

	// Send back data to JS.
	[self
		sendDictionary: info
		forCallback: myPeripheral.connectCallbackId
		keepCallback: YES];
}

/**
 * Helper method.
 */
- (void) sendOkClearCallback: (NSString*)callbackId
{
	// Clear callback on the JS side.
	CDVPluginResult* result = [CDVPluginResult
		resultWithStatus: CDVCommandStatus_OK];
	[result setKeepCallbackAsBool: NO];
	[self.commandDelegate
		sendPluginResult: result
		callbackId: callbackId];
}

/**
 * Helper method.
 * Tell Cordova to clear the callback function associated
 * with the given callback id.
 */
- (void) sendNoResultClearCallback: (NSString*)callbackId
{
	// Clear callback on the JS side.
	CDVPluginResult* result = [CDVPluginResult
		resultWithStatus: CDVCommandStatus_NO_RESULT];
	[result setKeepCallbackAsBool: NO];
	[self.commandDelegate
		sendPluginResult: result
		callbackId: callbackId];
}

/**
 * Helper method.
 * Send back an error message to Cordova.
 */
- (void) sendErrorMessage: (NSString*)errorMessage
	forCallback: (NSString*)callbackId
{
	CDVPluginResult* result = [CDVPluginResult
		resultWithStatus: CDVCommandStatus_ERROR
		messageAsString: errorMessage];
	[self.commandDelegate
		sendPluginResult: result
		callbackId: callbackId];
}

/**
 * Helper method.
 * Send back a dictionary object to Cordova.
 */
- (void) sendDictionary: (NSDictionary*)dictionary
	forCallback: (NSString*)callbackId
	keepCallback: (BOOL) keep
{
	CDVPluginResult* result = [CDVPluginResult
		resultWithStatus: CDVCommandStatus_OK
		messageAsDictionary: dictionary];
	[result setKeepCallbackAsBool: keep];
	[self.commandDelegate
		sendPluginResult: result
		callbackId: callbackId];
}

/**
 * Helper method.
 * Send back an array to Cordova.
 */
- (void) sendArray: (NSArray*)array
	forCallback: (NSString*)callbackId
	keepCallback: (BOOL) keep
{
	CDVPluginResult* result = [CDVPluginResult
		resultWithStatus: CDVCommandStatus_OK
		messageAsArray: array];
	[result setKeepCallbackAsBool: keep];
	[self.commandDelegate
		sendPluginResult: result
		callbackId: callbackId];
}

/**
 * Helper method.
 * Send back an int value to Cordova.
 */
- (void) sendInt: (int)value
	forCallback: (NSString*)callbackId
	keepCallback: (BOOL) keep
{
	CDVPluginResult* result = [CDVPluginResult
		resultWithStatus: CDVCommandStatus_OK
		messageAsInt: value];
	[result setKeepCallbackAsBool: keep];
	[self.commandDelegate
		sendPluginResult: result
		callbackId: callbackId];
}

/**
 * Helper method.
 * Send back a byte buffer to Cordova.
 */
- (void) sendBuffer: (NSData*)buffer
	forCallback: (NSString*)callbackId
	keepCallback: (BOOL) keep
{
	//NSLog(@"sending buffer: %@", buffer);
	//NSLog(@"sending buffer: %i", [buffer length]);
	//assert([buffer length] > 0);

	CDVPluginResult* result = [CDVPluginResult
		resultWithStatus: CDVCommandStatus_OK
		messageAsArrayBuffer: buffer];
	[result setKeepCallbackAsBool: keep];
	[self.commandDelegate
		sendPluginResult: result
		callbackId: callbackId];
}

@end

/*
Here is how to make an alert box, if it should be needed:
UIAlertView *alert = [[UIAlertView alloc]
	initWithTitle: @"No network connection"
    message:@"You must be connected to the internet to use this app."
    delegate:nil
    cancelButtonTitle:@"OK"
    otherButtonTitles:nil];
[alert show];
http://stackoverflow.com/questions/5763581/uialertview-button-action/5763609#5763609
*/
