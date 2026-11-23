------------------------------------------------------------------------------
--  Standalone BME280 driver for the SPI2 / SPI_Bus wiring (CS on PB11).
--
--  Modeled on Ada_Drivers_Library's BMP280 package
--  (components/src/sensors/combined/BMP280) without modifying the
--  library. Adds humidity: calibration H1 at 16#A1#, H2-H6 at 16#E1# ..
--  16#E7# (H4/H5 nibble-packed), ctrl_hum at 16#F2# (written before
--  ctrl_meas so it takes effect), data at 16#FD# .. 16#FE#, and the
--  Bosch integer humidity compensation (Q22.10 %RH). Chip-ID must be
--  16#60#.
------------------------------------------------------------------------------

with HAL;        use HAL;
with Interfaces; use Interfaces;

package BME280 is

   Expected_Chip_ID : constant UInt8 := 16#60#;

   type Chip_ID is new UInt8;

   type Pressure is delta 0.0001 range 300.0 .. 1100.0; -- hPa
   type Temperature is delta 0.01 range -40.0 .. 85.0;  -- deg C
   type Humidity is delta 0.001 range 0.0 .. 100.0;     -- %RH

   type Power_Modes is (Sleep, Forced, Normal) with Size => UInt2'Size;

   type Resolution is
     (Skipped,
      Ultra_Low_Power,
      Low_Power,
      Standard_Resolution,
      High_Resolution,
      Ultra_High_Resolution)
     with Size => UInt3'Size;

   type Standby_Milliseconds is delta 0.01 range 0.05 .. 4000.00
     with Static_Predicate =>
       Standby_Milliseconds in
         0.5 | 62.5 | 125.0 | 250.0 | 500.0
           | 1000.0 | 2000.0 | 4000.0;

   type Filters is range 0 .. 7;

   type BME280_Sensor is limited private;

   procedure Initialize
     (This  : in out BME280_Sensor;
      Error : out Boolean);
   --  Uses SPI_Bus.Select_BME / Deselect_BME and SPI_2. Fails unless the
   --  chip-ID register 16#D0# (read bit already set) returns 16#60#.

   function Get_Chip_ID (This : BME280_Sensor) return Chip_ID;

   procedure Reset (This : BME280_Sensor);

   procedure Set_Power_Mode
     (This       : BME280_Sensor;
      Power_Mode : Power_Modes);

   procedure Set_Temp_Precision
     (This  : BME280_Sensor;
      Value : Resolution);

   procedure Set_Press_Precision
     (This  : BME280_Sensor;
      Value : Resolution);

   procedure Set_Hum_Precision
     (This  : BME280_Sensor;
      Value : Resolution);
   --  Writes ctrl_hum (16#F2#) and then rewrites ctrl_meas so the new
   --  humidity oversampling takes effect, as required by the datasheet.

   procedure Set_Time_Standby
     (This         : BME280_Sensor;
      Time_Standby : Standby_Milliseconds);

   procedure Set_Filter
     (This   : BME280_Sensor;
      Filter : Filters);

   function Get_Temperature (This : in out BME280_Sensor) return Temperature;
   function Get_Pressure    (This : in out BME280_Sensor) return Pressure;
   function Get_Humidity    (This : in out BME280_Sensor) return Humidity;
   --  Get_Humidity (and Get_Pressure) also sample temperature so that
   --  t_fine is up to date for compensation.

private

   for Power_Modes use
     (Sleep  => 2#00#,
      Forced => 2#01#,
      Normal => 2#11#);

   for Resolution use
     (Skipped               => 2#000#,
      Ultra_Low_Power       => 2#001#,
      Low_Power             => 2#010#,
      Standard_Resolution   => 2#011#,
      High_Resolution       => 2#100#,
      Ultra_High_Resolution => 2#101#);

   type BME280_Sensor is limited record
      Ready  : Boolean := False;
      T_Fine : Integer_32 := 0;
      Dig_T1 : Integer_32 := 0;
      Dig_T2 : Integer_32 := 0;
      Dig_T3 : Integer_32 := 0;
      Dig_P1 : Integer_32 := 0;
      Dig_P2 : Integer_32 := 0;
      Dig_P3 : Integer_32 := 0;
      Dig_P4 : Integer_32 := 0;
      Dig_P5 : Integer_32 := 0;
      Dig_P6 : Integer_32 := 0;
      Dig_P7 : Integer_32 := 0;
      Dig_P8 : Integer_32 := 0;
      Dig_P9 : Integer_32 := 0;
      Dig_H1 : Integer_32 := 0;
      Dig_H2 : Integer_32 := 0;
      Dig_H3 : Integer_32 := 0;
      Dig_H4 : Integer_32 := 0;
      Dig_H5 : Integer_32 := 0;
      Dig_H6 : Integer_32 := 0;
   end record;

end BME280;
