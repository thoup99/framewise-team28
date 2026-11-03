with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Framewise;

package body Timeline_View is
   overriding procedure Build_Items (W : in out Track_Widget) is
      use type Framewise.Time;
      G : constant Rectangle := Get_Geometry (W);
      Left : constant Pixel_Type := G.X + 110.0;
      Right : constant Pixel_Type := G.X + G.Width;
      Y : Pixel_Type := G.Y + 30.0;

      procedure Label (Area : Rectangle; Text : String) is
         I : Item := Make_Text (Label_Part, Area, Text, 2);
      begin
         I.Wrap_Text := False;
         Add_Item (W, I);
      end Label;
   begin
      Clear_Items (W);
      Add_Item (W, Make_Panel (Main_Part, G, 0));
      if W.Read_Sequence = null or else G.Width <= 110.0 then
         return;
      end if;
      declare
         Seq : constant Framewise.Session.Sequence_View := W.Read_Sequence.all;
         Step : constant Long_Float :=
           (if W.Zoom >= 80.0 then 1.0 elsif W.Zoom >= 24.0 then 5.0 else 10.0);
         T : Long_Float := Long_Float'Ceiling (W.First_Second / Step) * Step;
         X : Pixel_Type;
         Any_Track : Boolean := False;
      begin
         Label ((G.X + 8.0, G.Y + 4.0, 100.0, 24.0), "Track / s");
         loop
            X := Left + Pixel_Type ((T - W.First_Second) * W.Zoom);
            exit when X >= Right;
            Label ((X, G.Y + 4.0, 70.0, 24.0),
                   Framewise.Session.Image_Time
                     (Framewise.Time (T * Long_Float (Framewise.Timebase))));
            T := T + Step;
         end loop;
         for Track of Seq.Tracks loop
            if Track.Used then
               Any_Track := True;
               Label ((G.X + 8.0, Y + 8.0, 100.0, 28.0), Framewise.Image (Track.N));
               for I in 1 .. Track.Count loop
                  declare
                     C renames Track.Clips (I);
                     X1 : constant Long_Float :=
                       (Framewise.Seconds (C.Start) - W.First_Second) * W.Zoom;
                     X2 : constant Long_Float := X1 +
                       Framewise.Seconds (C.Src_Out - C.Src_In) * W.Zoom;
                     Visible_Left : constant Pixel_Type :=
                       Left + Pixel_Type (Long_Float'Max (0.0, X1));
                     Visible_Right : constant Pixel_Type :=
                       Left + Pixel_Type (Long_Float'Min (Long_Float (Right - Left), X2));
                  begin
                     if Visible_Right > Visible_Left then
                        Add_Item (W, Make_Panel (Indicator_Part,
                          (Visible_Left, Y + 4.0, Visible_Right - Visible_Left, 36.0), 1));
                        Label ((Visible_Left + 3.0, Y + 10.0,
                                Pixel_Type'Max (0.0, Visible_Right - Visible_Left - 6.0),
                                24.0), Framewise.Image (C.N));
                     end if;
                  end;
               end loop;
               Y := Y + 48.0;
            end if;
         end loop;
         if not Any_Track then
            Label ((Left, Y, Right - Left, 30.0), "No tracks. Load a project below.");
         end if;
      end;
   end Build_Items;
end Timeline_View;
