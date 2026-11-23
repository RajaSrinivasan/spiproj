with STM32.Device; use STM32.Device;
with STM32.SPI;    use STM32.SPI;

with SPI_Bus;

package body BME280 is

   Reg_Id        : constant UInt8 := 16#D0#;
   Reg_Reset     : constant UInt8 := 16#E0#;
   Reg_Ctrl_Hum  : constant UInt8 := 16#F2#;
   Reg_Ctrl_Meas : constant UInt8 := 16#F4#;
   Reg_Config    : constant UInt8 := 16#F5#;
   Reg_Data      : constant UInt8 := 16#F7#;  --  press_msb, 8-byte burst
   Reg_Calib_TP  : constant UInt8 := 16#88#;
   Reg_Calib_H1  : constant UInt8 := 16#A1#;
   Reg_Calib_H2  : constant UInt8 := 16#E1#;

   Reset_Value : constant UInt8 := 16#B6#;

   type Ctrl_Meas_Register is record
      Mode   : Power_Modes;
      Osrs_P : Resolution;
      Osrs_T : Resolution;
   end record with Size => 8;

   for Ctrl_Meas_Register use record
      Mode   at 0 range 0 .. 1;
      Osrs_P at 0 range 2 .. 4;
      Osrs_T at 0 range 5 .. 7;
   end record;

   type Ctrl_Hum_Register is record
      Osrs_H   : Resolution;
      Reserved : UInt5;
   end record with Size => 8;

   for Ctrl_Hum_Register use record
      Osrs_H   at 0 range 0 .. 2;
      Reserved at 0 range 3 .. 7;
   end record;

   type Config_Register is record
      SPI3W_En : Bit;
      Reserved : Bit;
      Filter   : UInt3;
      T_SB     : UInt3;
   end record with Size => 8;

   for Config_Register use record
      SPI3W_En at 0 range 0 .. 0;
      Reserved at 0 range 1 .. 1;
      Filter   at 0 range 2 .. 4;
      T_SB     at 0 range 5 .. 7;
   end record;

   function Transfer (Outgoing : UInt8) return UInt8;
   function Read_Register (Addr : UInt8) return UInt8;
   procedure Write_Register (Addr : UInt8; Data : UInt8);
   procedure Read_Burst (Addr : UInt8; Data : out UInt8_Array);
   function To_Integer_8 (B : UInt8) return Integer_8;
   function To_Integer_16 (Lo, Hi : UInt8) return Integer_16;
   function Time_Standby_To_UInt3
     (Time_Standby : Standby_Milliseconds) return UInt3;
   procedure Read_Trim (This : in out BME280_Sensor);
   procedure Sample_Raw
     (This  : in out BME280_Sensor;
      Adc_T : out Integer_32;
      Adc_P : out Integer_32;
      Adc_H : out Integer_32);
   function Compute_T_Fine
     (This : BME280_Sensor; Adc_T : Integer_32) return Integer_32;
   function Compensate_Humidity
     (This : BME280_Sensor; Adc_H : Integer_32) return UInt32;

   --------------
   -- Transfer --
   --------------

   function Transfer (Outgoing : UInt8) return UInt8 is
      Incoming : UInt8;
   begin
      Transmit_Receive (SPI_2, Outgoing, Incoming);
      return Incoming;
   end Transfer;

   -------------------
   -- Read_Register --
   -------------------

   function Read_Register (Addr : UInt8) return UInt8 is
      Ignored : UInt8;
      Value   : UInt8;
      pragma Unreferenced (Ignored);
   begin
      --  The BME280 treats the transaction as a read when bit 7 of the
      --  first byte is set (same convention as the library BMP280 driver).
      SPI_Bus.Select_BME;
      Ignored := Transfer (Addr or 16#80#);
      Value := Transfer (16#00#);
      SPI_Bus.Deselect_BME;
      return Value;
   end Read_Register;

   --------------------
   -- Write_Register --
   --------------------

   procedure Write_Register (Addr : UInt8; Data : UInt8) is
      Ignored : UInt8;
      pragma Unreferenced (Ignored);
   begin
      SPI_Bus.Select_BME;
      Ignored := Transfer (Addr and 16#7F#);
      Ignored := Transfer (Data);
      SPI_Bus.Deselect_BME;
   end Write_Register;

   ----------------
   -- Read_Burst --
   ----------------

   procedure Read_Burst (Addr : UInt8; Data : out UInt8_Array) is
      Ignored : UInt8;
      pragma Unreferenced (Ignored);
   begin
      SPI_Bus.Select_BME;
      Ignored := Transfer (Addr or 16#80#);
      for I in Data'Range loop
         Data (I) := Transfer (16#00#);
      end loop;
      SPI_Bus.Deselect_BME;
   end Read_Burst;

   ------------------
   -- To_Integer_8 --
   ------------------

   function To_Integer_8 (B : UInt8) return Integer_8 is
      Local  : UInt8 := B;
      Result : Integer_8 with Import, Address => Local'Address;
   begin
      return Result;
   end To_Integer_8;

   -------------------
   -- To_Integer_16 --
   -------------------

   function To_Integer_16 (Lo, Hi : UInt8) return Integer_16 is
      Tmp    : UInt16 := UInt16 (Lo) or Shift_Left (UInt16 (Hi), 8);
      Result : Integer_16 with Import, Address => Tmp'Address;
   begin
      return Result;
   end To_Integer_16;

   --------------------------
   -- Time_Standby_To_UInt3 --
   --------------------------

   function Time_Standby_To_UInt3
     (Time_Standby : Standby_Milliseconds) return UInt3 is
   begin
      return (if    Time_Standby = 0.5    then 2#000#
              elsif Time_Standby = 62.5   then 2#001#
              elsif Time_Standby = 125.0  then 2#010#
              elsif Time_Standby = 250.0  then 2#011#
              elsif Time_Standby = 500.0  then 2#100#
              elsif Time_Standby = 1000.0 then 2#101#
              elsif Time_Standby = 2000.0 then 2#110#
              else  2#111#);
   end Time_Standby_To_UInt3;

   ---------------
   -- Read_Trim --
   ---------------

   procedure Read_Trim (This : in out BME280_Sensor) is
      TP : UInt8_Array (0 .. 23);
      H1 : UInt8;
      H  : UInt8_Array (0 .. 6);
   begin
      Read_Burst (Reg_Calib_TP, TP);
      H1 := Read_Register (Reg_Calib_H1);
      Read_Burst (Reg_Calib_H2, H);

      This.Dig_T1 := Integer_32 (UInt16 (TP (0)) or Shift_Left (UInt16 (TP (1)), 8));
      This.Dig_T2 := Integer_32 (To_Integer_16 (TP (2), TP (3)));
      This.Dig_T3 := Integer_32 (To_Integer_16 (TP (4), TP (5)));

      This.Dig_P1 := Integer_32 (UInt16 (TP (6)) or Shift_Left (UInt16 (TP (7)), 8));
      This.Dig_P2 := Integer_32 (To_Integer_16 (TP (8), TP (9)));
      This.Dig_P3 := Integer_32 (To_Integer_16 (TP (10), TP (11)));
      This.Dig_P4 := Integer_32 (To_Integer_16 (TP (12), TP (13)));
      This.Dig_P5 := Integer_32 (To_Integer_16 (TP (14), TP (15)));
      This.Dig_P6 := Integer_32 (To_Integer_16 (TP (16), TP (17)));
      This.Dig_P7 := Integer_32 (To_Integer_16 (TP (18), TP (19)));
      This.Dig_P8 := Integer_32 (To_Integer_16 (TP (20), TP (21)));
      This.Dig_P9 := Integer_32 (To_Integer_16 (TP (22), TP (23)));

      This.Dig_H1 := Integer_32 (H1);
      This.Dig_H2 := Integer_32 (To_Integer_16 (H (0), H (1)));
      This.Dig_H3 := Integer_32 (H (2));
      --  H4 / H5 are 12-bit signed, packed across 16#E4# .. 16#E6#.
      --  The official Bosch unpacking is (int8)E4 * 16 + (E5 & 0x0F)
      --  and (int8)E6 * 16 + (E5 >> 4).
      This.Dig_H4 := Integer_32 (To_Integer_8 (H (3))) * 16
                     + Integer_32 (H (4) and 16#0F#);
      This.Dig_H5 := Integer_32 (To_Integer_8 (H (5))) * 16
                     + Integer_32 (Shift_Right (H (4), 4));
      This.Dig_H6 := Integer_32 (To_Integer_8 (H (6)));
   end Read_Trim;

   -----------------
   -- Sample_Raw --
   -----------------

   procedure Sample_Raw
     (This  : in out BME280_Sensor;
      Adc_T : out Integer_32;
      Adc_P : out Integer_32;
      Adc_H : out Integer_32)
   is
      Data : UInt8_Array (0 .. 7);
   begin
      Read_Burst (Reg_Data, Data);
      Adc_P := Integer_32
        (Shift_Right
           (Shift_Left (UInt32 (Data (0)), 16)
            or Shift_Left (UInt32 (Data (1)), 8)
            or UInt32 (Data (2)),
            4));
      Adc_T := Integer_32
        (Shift_Right
           (Shift_Left (UInt32 (Data (3)), 16)
            or Shift_Left (UInt32 (Data (4)), 8)
            or UInt32 (Data (5)),
            4));
      Adc_H := Integer_32
        (Shift_Left (UInt32 (Data (6)), 8) or UInt32 (Data (7)));
      This.T_Fine := Compute_T_Fine (This, Adc_T);
   end Sample_Raw;

   --------------------
   -- Compute_T_Fine --
   --------------------

   function Compute_T_Fine
     (This : BME280_Sensor; Adc_T : Integer_32) return Integer_32
   is
      --  Same integer formula used by the library BMP280 driver.
      Var1 : Integer_32;
      Var2 : Integer_32;
   begin
      Var1 := ((Adc_T / 8 - This.Dig_T1 * 2) * This.Dig_T2) / 2048;
      Var2 := Adc_T / 16 - This.Dig_T1;
      Var2 := (((Var2 * Var2) / 4096) * This.Dig_T3) / 16384;
      return Var1 + Var2;
   end Compute_T_Fine;

   -------------------------
   -- Compensate_Humidity --
   -------------------------

   function Compensate_Humidity
     (This : BME280_Sensor; Adc_H : Integer_32) return UInt32
   is
      --  Bosch BME280 integer compensation, returning %RH in Q22.10
      --  (value / 1024.0 is percent relative humidity). Intermediates
      --  are 64-bit so a build with overflow checks stays well-defined;
      --  the shifts and terms are those of the datasheet.
      V  : Integer_64;
      V2 : Integer_64;
   begin
      V := Integer_64 (This.T_Fine) - 76800;

      V2 := (((((((V * Integer_64 (This.Dig_H6)) / 1024)
                * ((V * Integer_64 (This.Dig_H3)) / 2048 + 32768)) / 1024)
               + 2097152)
              * Integer_64 (This.Dig_H2) + 8192) / 16384);

      V := (((((Integer_64 (Adc_H) * 16384)
               - (Integer_64 (This.Dig_H4) * 1048576)
               - (Integer_64 (This.Dig_H5) * V)) + 16384) / 32768) * V2);

      V := V - (((((V / 32768) * (V / 32768)) / 128)
                 * Integer_64 (This.Dig_H1)) / 16);

      if V < 0 then
         V := 0;
      elsif V > 419430400 then
         V := 419430400;
      end if;

      return UInt32 (V / 4096);
   end Compensate_Humidity;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (This  : in out BME280_Sensor;
      Error : out Boolean)
   is
      Id : UInt8;
   begin
      This.Ready := False;
      Id := Read_Register (Reg_Id);
      if Id /= Expected_Chip_ID then
         Error := True;
         return;
      end if;
      Read_Trim (This);
      This.Ready := True;
      Error := False;
   end Initialize;

   -----------------
   -- Get_Chip_ID --
   -----------------

   function Get_Chip_ID (This : BME280_Sensor) return Chip_ID is
      pragma Unreferenced (This);
   begin
      return Chip_ID (Read_Register (Reg_Id));
   end Get_Chip_ID;

   -----------
   -- Reset --
   -----------

   procedure Reset (This : BME280_Sensor) is
      pragma Unreferenced (This);
   begin
      Write_Register (Reg_Reset, Reset_Value);
   end Reset;

   --------------------
   -- Set_Power_Mode --
   --------------------

   procedure Set_Power_Mode
     (This       : BME280_Sensor;
      Power_Mode : Power_Modes)
   is
      pragma Unreferenced (This);
      Data     : UInt8 := Read_Register (Reg_Ctrl_Meas);
      Register : Ctrl_Meas_Register with Import, Address => Data'Address;
   begin
      Register.Mode := Power_Mode;
      Write_Register (Reg_Ctrl_Meas, Data);
   end Set_Power_Mode;

   ------------------------
   -- Set_Temp_Precision --
   ------------------------

   procedure Set_Temp_Precision
     (This  : BME280_Sensor;
      Value : Resolution)
   is
      pragma Unreferenced (This);
      Data     : UInt8 := Read_Register (Reg_Ctrl_Meas);
      Register : Ctrl_Meas_Register with Import, Address => Data'Address;
   begin
      Register.Osrs_T := Value;
      Write_Register (Reg_Ctrl_Meas, Data);
   end Set_Temp_Precision;

   -------------------------
   -- Set_Press_Precision --
   -------------------------

   procedure Set_Press_Precision
     (This  : BME280_Sensor;
      Value : Resolution)
   is
      pragma Unreferenced (This);
      Data     : UInt8 := Read_Register (Reg_Ctrl_Meas);
      Register : Ctrl_Meas_Register with Import, Address => Data'Address;
   begin
      Register.Osrs_P := Value;
      Write_Register (Reg_Ctrl_Meas, Data);
   end Set_Press_Precision;

   -----------------------
   -- Set_Hum_Precision --
   -----------------------

   procedure Set_Hum_Precision
     (This  : BME280_Sensor;
      Value : Resolution)
   is
      pragma Unreferenced (This);
      Hum_Data  : UInt8 := Read_Register (Reg_Ctrl_Hum);
      Hum_Reg   : Ctrl_Hum_Register with Import, Address => Hum_Data'Address;
      Meas_Data : UInt8;
   begin
      Hum_Reg.Osrs_H := Value;
      Write_Register (Reg_Ctrl_Hum, Hum_Data);
      --  Datasheet: changes to ctrl_hum take effect only after the next
      --  write to ctrl_meas.
      Meas_Data := Read_Register (Reg_Ctrl_Meas);
      Write_Register (Reg_Ctrl_Meas, Meas_Data);
   end Set_Hum_Precision;

   ----------------------
   -- Set_Time_Standby --
   ----------------------

   procedure Set_Time_Standby
     (This         : BME280_Sensor;
      Time_Standby : Standby_Milliseconds)
   is
      pragma Unreferenced (This);
      Data     : UInt8 := Read_Register (Reg_Config);
      Register : Config_Register with Import, Address => Data'Address;
   begin
      Register.T_SB := Time_Standby_To_UInt3 (Time_Standby);
      Write_Register (Reg_Config, Data);
   end Set_Time_Standby;

   ----------------
   -- Set_Filter --
   ----------------

   procedure Set_Filter
     (This   : BME280_Sensor;
      Filter : Filters)
   is
      pragma Unreferenced (This);
      Data     : UInt8 := Read_Register (Reg_Config);
      Register : Config_Register with Import, Address => Data'Address;
   begin
      Register.Filter := UInt3 (Filter);
      Write_Register (Reg_Config, Data);
   end Set_Filter;

   ---------------------
   -- Get_Temperature --
   ---------------------

   function Get_Temperature (This : in out BME280_Sensor) return Temperature is
      Adc_T, Adc_P, Adc_H : Integer_32;
      T                   : Integer_32;
   begin
      Sample_Raw (This, Adc_T, Adc_P, Adc_H);
      T := (This.T_Fine * 5 + 128) / 256;
      return Temperature (Float (T) / 100.0);
   end Get_Temperature;

   ------------------
   -- Get_Pressure --
   ------------------

   function Get_Pressure (This : in out BME280_Sensor) return Pressure is
      --  Same 64-bit integer formula as the library BMP280 driver.
      Adc_T, Adc_P, Adc_H : Integer_32;
      Var1, Var2, P       : Integer_64;
   begin
      Sample_Raw (This, Adc_T, Adc_P, Adc_H);

      Var1 := Integer_64 (This.T_Fine - 128000);
      Var2 := Var1 * Var1 * Integer_64 (This.Dig_P6);
      Var2 := Var2 + (Var1 * Integer_64 (This.Dig_P5)) * 131072;
      Var2 := Var2 + (Integer_64 (This.Dig_P4) * 34359738368);
      Var1 := ((Var1 * Var1 * Integer_64 (This.Dig_P3)) / 256) +
        ((Var1 * Integer_64 (This.Dig_P2)) * 4096);
      Var1 := ((140737488355328 + Var1) * Integer_64 (This.Dig_P1))
        / 8589934592;

      if Var1 = 0 then
         return Pressure'First;
      end if;

      P := 1048576 - Integer_64 (Adc_P);
      P := ((P * 2147483648 - Var2) * 3125) / Var1;
      Var1 := (Integer_64 (This.Dig_P9) * (P / 8192) * (P / 8192))
        / 33554432;
      Var2 := (Integer_64 (This.Dig_P8) * P) / 524288;
      P := (((P + Var1 + Var2) / 256) + (Integer_64 (This.Dig_P7) * 16));

      return Pressure (Float (P) / 25600.0);
   end Get_Pressure;

   ------------------
   -- Get_Humidity --
   ------------------

   function Get_Humidity (This : in out BME280_Sensor) return Humidity is
      Adc_T, Adc_P, Adc_H : Integer_32;
      Q22_10              : UInt32;
   begin
      Sample_Raw (This, Adc_T, Adc_P, Adc_H);
      Q22_10 := Compensate_Humidity (This, Adc_H);
      declare
         Percent : constant Float := Float (Q22_10) / 1024.0;
      begin
         if Percent < Float (Humidity'First) then
            return Humidity'First;
         elsif Percent > Float (Humidity'Last) then
            return Humidity'Last;
         else
            return Humidity (Percent);
         end if;
      end;
   end Get_Humidity;

end BME280;
