package body Framewise.Timeline with SPARK_Mode is

   -----------------
   -- Find_Source --
   -----------------

   function Find_Source (S : Sequence; N : Name) return Source_Id is
   begin
      for I in S.Sources'Range loop
         if S.Sources (I).Used and then S.Sources (I).N = N then
            return I;
         end if;
      end loop;
      return No_Source;
   end Find_Source;

   ----------------
   -- Find_Track --
   ----------------

   function Find_Track (S : Sequence; N : Name) return Track_Id is
   begin
      for T in S.Tracks'Range loop
         if S.Tracks (T).Used and then S.Tracks (T).N = N then
            return T;
         end if;
      end loop;
      return 0;
   end Find_Track;

   ---------------
   -- Find_Clip --
   ---------------

   procedure Find_Clip
     (S : Sequence; N : Name; T : out Track_Id; I : out Clip_Index) is
   begin
      for TT in S.Tracks'Range loop
         if S.Tracks (TT).Used then
            for II in 1 .. S.Tracks (TT).Count loop
               if S.Tracks (TT).Clips (II).N = N then
                  T := TT;
                  I := II;
                  return;
               end if;
            end loop;
         end if;
      end loop;
      T := 0;
      I := 0;
   end Find_Clip;

   ---------------
   -- Track_End --
   ---------------

   function Track_End (S : Sequence; T : Track_Id) return Time is
      Tr : Track renames S.Tracks (T);
   begin
      if not Tr.Used or else Tr.Count = 0 then
         return 0;
      end if;
      return Ends (Tr.Clips (Tr.Count));
   end Track_End;

   ------------------
   -- Sequence_End --
   ------------------

   function Sequence_End (S : Sequence) return Time is
      E : Time := 0;
   begin
      for T in S.Tracks'Range loop
         E := Time'Max (E, Track_End (S, T));
      end loop;
      return E;
   end Sequence_End;

   -----------
   -- Clear --
   -----------

   procedure Clear (S : out Sequence) is
   begin
      S := (Sources => [others => <>], Tracks => [others => <>]);
   end Clear;

   ----------------
   -- Add_Source --
   ----------------

   procedure Add_Source
     (S : in out Sequence; N : Name; File : Path; Length : Duration_T;
      Kind : Media_Kind; Ok : out Boolean) is
   begin
      Ok := False;
      if Find_Source (S, N) /= No_Source then
         return;
      end if;
      for I in S.Sources'Range loop
         --  P1: source additions cannot invalidate existing track clips.
         pragma Loop_Invariant (Well_Formed (S));
         if not S.Sources (I).Used then
            S.Sources (I) := (Used => True, N => N, File => File, Length => Length, Kind => Kind);
            pragma Assert (Well_Formed (S));
            Ok := True;
            return;
         end if;
      end loop;
   end Add_Source;

   ---------------
   -- Add_Track --
   ---------------

   procedure Add_Track (S : in out Sequence; N : Name; Kind : Media_Kind; Ok : out Boolean) is
   begin
      Ok := False;
      if Find_Track (S, N) /= 0 then
         return;
      end if;
      for T in S.Tracks'Range loop
         --  P1: unmodified tracks keep the original well-formed state.
         pragma Loop_Invariant (Well_Formed (S));
         if not S.Tracks (T).Used then
            S.Tracks (T).Used := True;
            S.Tracks (T).N := N;
            S.Tracks (T).Kind := Kind;
            S.Tracks (T).Count := 0;
            pragma Assert (Well_Formed (S));
            Ok := True;
            return;
         end if;
      end loop;
   end Add_Track;

   ---------------------------------------------------------------------
   --  Helpers on one track
   ---------------------------------------------------------------------

   --  True when a clip [Start, Start + Len) would overlap any clip on Tr
   --  other than slot Skip (0 = none).
   function Overlaps (Tr : Track; Start, Len : Time; Skip : Clip_Index) return Boolean
     with Pre => Start <= Time'Last / 2 and then Len <= Time'Last / 2
                 and then Tr.Count <= Max_Clips
                 and then (for all I in 1 .. Tr.Count =>
                             Tr.Clips (I).Src_In <= Tr.Clips (I).Src_Out
                             and then Tr.Clips (I).Start <= Time'Last / 2
                             and then Tr.Clips (I).Src_Out <= Time'Last / 2),
          --  Postcondition: the result is True exactly when some clip other
          --  than Skip intersects [Start, Start + Len). Without this, a
          --  caller that gets False learns nothing about the track.
          Post => Overlaps'Result =
                    (for some I in 1 .. Tr.Count =>
                       I /= Skip
                       and then Start < Ends (Tr.Clips (I))
                       and then Tr.Clips (I).Start < Start + Len);

   function Insert_Pos (Tr : Track; C : Clip) return Clip_Index
     with Pre  => Tr.Count < Max_Clips,
          --  Postcondition: the result is the first slot whose clip starts
          --  after C (or Count + 1 if none does). Every clip before it
          --  starts at or before C.
          Post => Insert_Pos'Result in 1 .. Tr.Count + 1
                  and then (for all K in 1 .. Insert_Pos'Result - 1 =>
                              Tr.Clips (K).Start <= C.Start)
                  and then (if Insert_Pos'Result <= Tr.Count
                            then Tr.Clips (Insert_Pos'Result).Start > C.Start);

   procedure Insert_Sorted (Tr : in out Track; C : Clip)
     with Pre  => Tr.Count < Max_Clips,
          --  Postcondition: C is placed at Insert_Pos, clips before it are
          --  unchanged, and clips after it are the old ones shifted right
          --  by one. 'Old = the value when Insert_Sorted was called.
          Post => Tr.Used = Tr.Used'Old
                  and then Tr.Count = Tr.Count'Old + 1
                  and then (for all K in 1 .. Insert_Pos (Tr'Old, C) - 1 =>
                              Tr.Clips (K) = Tr.Clips'Old (K))
                  and then Tr.Clips (Insert_Pos (Tr'Old, C)) = C
                  and then (for all K in Insert_Pos (Tr'Old, C) + 1 .. Tr.Count =>
                              Tr.Clips (K) = Tr.Clips'Old (K - 1));

   procedure Remove_At (Tr : in out Track; I : Clip_Index)
     --  I must be the index of an existing clip.
     with Pre  => I in 1 .. Tr.Count,
          --  P1: describe exactly what Remove_At does, so Delete can
          --  prove the track is still sorted after the removal.
          --  'Old = the value when Remove_At was called.
          --  The track is still marked as used.
          Post => Tr.Used = Tr.Used'Old
                  --  One clip fewer.
                  and then Tr.Count = Tr.Count'Old - 1
                  --  Clips before I are unchanged.
                  and then (for all K in 1 .. I - 1 =>
                              Tr.Clips (K) = Tr.Clips'Old (K))
                  --  Clips from I on are the old ones shifted left by one.
                  and then (for all K in I .. Tr.Count =>
                              Tr.Clips (K) = Tr.Clips'Old (K + 1));

   function Overlaps (Tr : Track; Start, Len : Time; Skip : Clip_Index) return Boolean
   is
   begin
      for I in 1 .. Tr.Count loop
         if I /= Skip then
            declare
               C : Clip renames Tr.Clips (I);
            begin
               if Start < Ends (C) and then C.Start < Start + Len then
                  return True;
               end if;
            end;
         end if;
         --  Every clip checked so far (1 .. I) is either Skip or does not
         --  intersect the new window. If the loop finishes, that covers
         --  every clip, which is what the postcondition needs for False.
         pragma Loop_Invariant
           (for all K in 1 .. I =>
              K = Skip
              or else not (Start < Ends (Tr.Clips (K))
                           and then Tr.Clips (K).Start < Start + Len));
      end loop;
      return False;
   end Overlaps;

   --  First slot whose clip starts after C, or Count + 1 if none does.
   function Insert_Pos (Tr : Track; C : Clip) return Clip_Index is
   begin
      for I in 1 .. Tr.Count loop
         if Tr.Clips (I).Start > C.Start then
            return I;
         end if;
         --  Every clip checked so far starts at or before C.
         pragma Loop_Invariant
           (for all K in 1 .. I => Tr.Clips (K).Start <= C.Start);
      end loop;
      return Tr.Count + 1;
   end Insert_Pos;

   --  Insert C into Tr keeping clips sorted by Start. Caller has checked
   --  no overlap and room.
   procedure Insert_Sorted (Tr : in out Track; C : Clip) is
      Pos : constant Clip_Index := Insert_Pos (Tr, C);
   begin
      --  Shift clips Pos .. Count one slot to the right, starting from the
      --  end so nothing is overwritten before it is copied.
      for I in reverse Pos .. Tr.Count loop
         Tr.Clips (I + 1) := Tr.Clips (I);
         --  'Loop_Entry = the value just before the loop started.
         pragma Loop_Invariant
           --  Clips before I: not reached yet, still the originals.
           ((for all K in 1 .. I - 1 =>
               Tr.Clips (K) = Tr.Clips'Loop_Entry (K))
            --  Clips after I: already shifted right by one.
            and then (for all K in I + 1 .. Tr.Count + 1 =>
                        Tr.Clips (K) = Tr.Clips'Loop_Entry (K - 1)));
      end loop;
      --  Slot Pos is now free (its old clip moved to Pos + 1).
      Tr.Clips (Pos) := C;
      Tr.Count := Tr.Count + 1;
   end Insert_Sorted;

   procedure Remove_At (Tr : in out Track; I : Clip_Index) is
   begin
      --  Shift every clip after I one slot to the left, overwriting I.
      for J in I .. Tr.Count - 1 loop
         Tr.Clips (J) := Tr.Clips (J + 1);
         --  P1: what is true after each pass of the loop.
         --  'Loop_Entry = the value just before the loop started.
         pragma Loop_Invariant
           --  Clips before I: never touched.
           ((for all K in 1 .. I - 1 =>
               Tr.Clips (K) = Tr.Clips'Loop_Entry (K))
            --  Clips I .. J: already shifted left by one.
            and then (for all K in I .. J =>
                        Tr.Clips (K) = Tr.Clips'Loop_Entry (K + 1))
            --  Clips after J: not reached yet, still the originals.
            and then (for all K in J + 1 .. Tr.Count =>
                        Tr.Clips (K) = Tr.Clips'Loop_Entry (K)));
      end loop;
      --  The last slot is now a stale copy; dropping Count hides it.
      Tr.Count := Tr.Count - 1;
   end Remove_At;

   -----------
   -- Place --
   -----------

   procedure Place
     (S : in out Sequence; Clip_Name : Name; On : Name; From : Name;
      Src_In, Src_Out, Start : Time; Ok : out Boolean)
   is
      T   : constant Track_Id  := Find_Track (S, On);
      Src : constant Source_Id := Find_Source (S, From);
      DT  : Track_Id;
      DI  : Clip_Index;
      C   : Clip;
   begin
      Ok := False;
      if T = 0 or else Src = No_Source then
         return;
      end if;
      Find_Clip (S, Clip_Name, DT, DI);
      if DT /= 0 then
         return;  --  duplicate name
      end if;
      C := (N => Clip_Name, Src => Src, Src_In => Src_In, Src_Out => Src_Out, Start => Start);
      if not Clip_OK (S, C) then
         return;
      end if;
      if S.Tracks (T).Count = Max_Clips then
         return;
      end if;
      if Overlaps (S.Tracks (T), Start, Src_Out - Src_In, 0) then
         return;
      end if;
      Insert_Sorted (S.Tracks (T), C);
      Ok := True;
   end Place;

   ----------
   -- Move --
   ----------

   procedure Move (S : in out Sequence; Clip_Name : Name; To : Time; Ok : out Boolean) is
      T : Track_Id;
      I : Clip_Index;
      C : Clip;
   begin
      Ok := False;
      Find_Clip (S, Clip_Name, T, I);
      if T = 0 or else To > Time'Last / 2 then
         return;
      end if;
      C := S.Tracks (T).Clips (I);
      if Overlaps (S.Tracks (T), To, Length (C), I) then
         return;
      end if;
      C.Start := To;
      Remove_At (S.Tracks (T), I);
      Insert_Sorted (S.Tracks (T), C);
      Ok := True;
   end Move;

   ----------
   -- Trim --
   ----------

   procedure Trim
     (S : in out Sequence; Clip_Name : Name; New_In, New_Out : Time; Ok : out Boolean)
   is
      T : Track_Id;
      I : Clip_Index;
      C : Clip;
   begin
      Ok := False;
      Find_Clip (S, Clip_Name, T, I);
      if T = 0 then
         return;
      end if;
      C := S.Tracks (T).Clips (I);
      C.Src_In := New_In;
      C.Src_Out := New_Out;
      if not Clip_OK (S, C) then
         return;
      end if;
      if Overlaps (S.Tracks (T), C.Start, Length (C), I) then
         return;
      end if;
      S.Tracks (T).Clips (I) := C;
      Ok := True;
   end Trim;

   -----------
   -- Split --
   -----------

   procedure Split
     (S : in out Sequence; Clip_Name : Name; Start : Time; Right_Name : Name; Ok : out Boolean)
   is
      T  : Track_Id;
      I  : Clip_Index;
      DT : Track_Id;
      DI : Clip_Index;
      L, R : Clip;
      Offset : Time;
   begin
      Ok := False;
      Find_Clip (S, Clip_Name, T, I);
      if T = 0 then
         return;
      end if;
      Find_Clip (S, Right_Name, DT, DI);
      if DT /= 0 then
         return;  --  right name taken
      end if;
      L := S.Tracks (T).Clips (I);
      if Start <= L.Start or else Start >= Ends (L) then
         return;  --  cut must be strictly inside
      end if;
      if S.Tracks (T).Count = Max_Clips then
         return;
      end if;
      Offset := Start - L.Start;
      R := (N => Right_Name, Src => L.Src, Src_In => L.Src_In + Offset,
            Src_Out => L.Src_Out, Start => Start);
      L.Src_Out := L.Src_In + Offset;
      --  L now ends exactly where R starts: Ends (L) = Start = R.Start. T3.
      S.Tracks (T).Clips (I) := L;
      Insert_Sorted (S.Tracks (T), R);
      Ok := True;
   end Split;

   ------------
   -- Delete --
   ------------

   procedure Delete (S : in out Sequence; Clip_Name : Name; Ok : out Boolean) is
      T : Track_Id;
      I : Clip_Index;
   begin
      Find_Clip (S, Clip_Name, T, I);
      if T = 0 then
         Ok := False;
         return;
      end if;
      Remove_At (S.Tracks (T), I);
      Ok := True;
   end Delete;

end Framewise.Timeline;
