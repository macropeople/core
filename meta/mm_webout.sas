/**
  @file mm_webout.sas
  @brief Send data to/from SAS Stored Processes
  @details This macro should be added to the start of each Stored Process,
  **immediately** followed by a call to:

        %mm_webout(FETCH)

    This will read all the input data and create same-named SAS datasets in the
    WORK library.  You can then insert your code, and send data back using the
    following syntax:

        data some datasets; * make some data ;
        retain some columns;
        run;

        %mm_webout(OPEN)
        %mm_webout(ARR,some)  * Array format, fast, suitable for large tables ;
        %mm_webout(OBJ,datasets) * Object format, easier to work with ;

    Finally, wrap everything up send some helpful system variables too

        %mm_webout(CLOSE)


  @param action Either FETCH, OPEN, ARR, OBJ or CLOSE
  @param ds The dataset to send back to the frontend

  @version 9.3
  @author Allan Bowe

**/
%macro mm_webout(action,ds);
%global _webin_file_count _webin_fileref1 _webin_name1 _program _debug;
%if &action=FETCH %then %do;
  %if &_debug ge 131 %then %do;
    options mprint notes mprintnest;
  %end;

  %let _webin_file_count=%eval(&_webin_file_count+0);
  /* now read in the data */
  %local i;
  %do i=1 %to &_webin_file_count;
    %if &_webin_file_count=1 %then %do;
      %let _webin_fileref1=&_webin_fileref;
      %let _webin_name1=&_webin_name;
    %end;
    data _null_;
      infile &&_webin_fileref&i termstr=crlf;
      input;
      call symputx('input_statement',_infile_);
      putlog "&&_webin_name&i input statement: "  _infile_;
      stop;
    data &&_webin_name&i;
      infile &&_webin_fileref&i firstobs=2 dsd termstr=crlf ;
      input &input_statement;
    run;
  %end;
%end;

%else %if &action=OPEN %then %do;
  /* setup json */
  data _null_;file _webout;
  %if &_debug ge 131 %then %do;
    put '>>weboutBEGIN<<';
  %end;
    put '{"START_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '"';
  run;

%end;

%else %if &action=ARR or &action=OBJ %then %do;
  options validvarname=upcase;

  data _null_;file _webout;
    put ", ""%lowcase(&ds)"":[";

  proc sort data=sashelp.vcolumn(where=(libname='WORK' & memname="%upcase(&ds)"))
    out=_data_;
    by varnum;

  data _null_; set _last_ end=last;
    call symputx(cats('name',_n_),name,'l');
    call symputx(cats('type',_n_),type,'l');
    call symputx(cats('len',_n_),length,'l');
    if last then call symputx('cols',_n_,'l');

  proc format; /* credit yabwon for special null removal */
    value bart ._ - .z = null;

  /* write to temp loc to avoid truncation - https://support.sas.com/kb/49/325.html */
  filename _sjs temp lrecl=131068 ;
  data _null_; file _sjs ;
    set &ds;
    format _numeric_ ;
    if _n_>1 then put "," @; put
    %if &action=ARR %then "[" ; %else "{" ;
    %local c; %do c=1 %to &cols;
      %if &c>1 %then  "," ;
      %if &action=OBJ %then """&&name&c"":" ;
       &&name&c
      %if &&type&c=char %then $quote%eval(&&len&c+2). ;
      %else bart. ;
      +(0)
    %end;
    %if &action=ARR %then "]" ; %else "}" ; ;
  /* now write the long strings to _webout 1 char at a time */
  data _null_;
    infile _sjs RECFM=N;
    file _webout RECFM=N;
    input string $CHAR1. @;
    put string $CHAR1. @;

  data _null_; file _webout;
    put "]";
  run;

%end;

%else %if &action=CLOSE %then %do;

  /* close off json */
  data _null_;file _webout mod;
    _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
    put ',"SYSUSERID" : "' "&sysuserid." '",';
    _METAUSER=quote(trim(symget('_METAUSER')));
    put '"_METAUSER": ' _METAUSER ',';
    _METAPERSON=quote(trim(symget('_METAPERSON')));
    put '"_METAPERSON": ' _METAPERSON ',';
    put '"_PROGRAM" : ' _PROGRAM ',';
    put '"END_DTTM" : "' "%sysfunc(datetime(),datetime20.3)" '" ';
    put "}" @;
  %if &_debug ge 131 %then %do;
    put '>>weboutEND<<';
  %end;
  run;

%end;

%mend;