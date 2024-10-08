; (C) March 29, 2002  M. Feliks

include sys.inc

LETTER_COLOR equ 40 - 8
TXT_COLOR equ 63
WAIT_TIME equ 300
DRAWING_SPEED equ 2

N_OFS equ 794
N_OFS2 equ 832

.model tiny
.code
.386

org 100h


entrypoint:

    call    do_startup

      ; get pointer to system font
    push    es
    mov     ax, 01130h
    mov     bh, 03h
    int     10h
    mov     word ptr [font_address + 0], bp
    mov     word ptr [font_address + 2], es
    pop     es

      ; set green palette
    mov     dx, 03c8h
    xor     ax, ax
    out     dx, al
    inc     dx
    mov     cx, 64
set_green:
    xor     al, al
    out     dx, al
    mov     al, ah
    out     dx, al
    xor     al, al
    out     dx, al
    inc     ah
    loop    set_green

      ; init speeds of letters in each column
    mov     di, offset let_speed
    mov     cx, 320 / 8
init_speed:
    push    cx
    call    random_num
    pop     cx
    and     ax, 3
    stosb
    dec     cx
    jnz     init_speed

do_frame:
    call    clear_buffer

      ; decide if it's needed to generate new
      ; letter table
    mov     ax, [frame_cnt]
    inc     ax
    and     ax, 7
    mov     [frame_cnt], ax
    jnz     next_rnd

      ; make new table
    mov     di, offset let_table
    mov     si, offset let_speed
    mov     cx, 320 / 8
make_new_x:
    mov     dx, 200 / 8
    xor     bx, bx
    lodsb
    movzx   bp, al
make_new_y:
    mov     al, [di + bx]
    or      al, al
    jnz     make_new_next

    push    cx
    push    dx
    push    bx
    call    random_num
    pop     bx
    pop     dx
    pop     cx
    mov     [di + bx], al

    dec     bp
    jle     make_new_next_col
make_new_next:
    inc     bx
    dec     dx
    jnz     make_new_y

    xor     bx, bx
    xor     al, al
    mov     bp, 200 / 8
make_new_clear_col:
    mov     [di + bx], al
    inc     bx
    dec     bp
    jnz     make_new_clear_col

      ; set new speed for current column
    push    cx
    call    random_num
    pop     cx
    and     ax, 3
    mov     [si - 1], al

make_new_next_col:
    add     di, 200 / 8
    dec     cx
    jnz     make_new_x
next_rnd:


      ; draw matrix code
    mov     si, offset let_table
    cld
    xor     cx, cx
draw_matrix_x:
    xor     dx, dx
draw_matrix_y:
    lodsb
    or      al, al
    jz      draw_matrix_skip
    push    si
    push    cx
    push    dx
    call    put_letter
    pop     dx
    pop     cx
    pop     si
draw_matrix_skip:
    add     dx, 8
    cmp     dx, 200
    jne     draw_matrix_y
    add     cx, 8
    cmp     cx, 320
    jne     draw_matrix_x

      ; draw text
    push    es
    mov     es, [buffer_seg]
    mov     si, [current_way]
    mov     cx, [txt_position]
    or      cx, cx
    jz      text_done
    cld
draw_text:
    lodsw
    mov     di, ax
    mov     al, [current_col]
    mov     ah, al
    mov     word ptr es:[di], ax
    mov     word ptr es:[di + 320], ax
    dec     cx
    jnz     draw_text
text_done:
    pop     es

      ; change text position
    mov     ax, [txt_position]
    add     ax, DRAWING_SPEED
    cmp     ax, [current_max]
    jb      text_pos_ok

      ; decrease text color
    mov     ax, [txt_wait]
    test    ax, 1
    jz      skip_new_color
    mov     al, [current_col]
    or      al, al
    jz      set_new_color
    dec     al
set_new_color:
    mov     [current_col], al
skip_new_color:

    mov     ax, [txt_wait]
    inc     ax
    cmp     ax, WAIT_TIME
    jb      text_wait

    xor     ax, ax
    mov     [txt_wait], ax
    mov     [txt_position], ax
    mov     al, TXT_COLOR
    mov     [current_col], al

      ; change way !
    mov     ax, [current_way]
    cmp     ax, offset way_data
    je      set_way2

    mov     ax, offset way_data
    mov     bx, N_OFS
    jmp     set_now
set_way2:
    mov     ax, offset way_data2
    mov     bx, N_OFS2
set_now:
    mov     [current_max], bx
    mov     [current_way], ax
    jmp     text_leave
text_wait:
    mov     [txt_wait], ax
    mov     ax, [current_max]
    dec     ax
text_pos_ok:
    mov     [txt_position], ax
text_leave:

comment #
      ; smooth screen (heavily optimized for speed
      ; but works only if there's no color bigger than
      ; 63 in a buffer !)
    push    es
    push    ds
    mov     ax, [buffer_seg]
    mov     ds, ax
    mov     es, ax

    xor     di, di
    xor     eax, eax
    mov     cx, 320 / 4
    cld
    rep     stosd

    mov     cx, (64000 - 320*2) / 4
    xor     bx, bx
sscr_loop:
    mov     eax, [di - 1]
    add     eax, [di + 1]
    add     eax, [di - 320]
    add     eax, [di + 320]
    and     eax, 0fcfcfcfch
    shr     eax, 2
    stosd
    dec     cx
    jnz     sscr_loop

    xor     eax, eax
    mov     cx, 320 / 4
    rep     stosd
    pop     ds
    pop     es #

    call    timer_wait
    call    copy_buffer

    mov     ah, 6h
    mov     dl, 0ffh
    int     21h
    jz      do_frame

    call    do_shutdown

;************************************************************
;    Prints a single letter
;    in: cx = x, dx = y, ax = letter
;************************************************************

put_letter:
    push    ds
    push    es
    mov     es, [buffer_seg]
    mov     di, dx
    shl     di, 6
    shl     dx, 8
    add     di, dx
    add     di, cx

    mov     si, word ptr [font_address + 0]
    mov     ds, word ptr [font_address + 2]
    and     ax, 255
    shl     ax, 3
    add     si, ax

    cld
    mov     ah, LETTER_COLOR
      ; modification !!! do not draw a full letter
      ; for better effect
    mov     dx, 5  ;8
pl_y:
    mov     cx, 5  ;8
    lodsb
pl_x:
    rcl     al, 1
    jnc     pl_next_pix
    mov     byte ptr es:[di], ah
pl_next_pix:
    inc     di
    dec     cx
    jnz     pl_x

    inc     ah
    add     di, 320 - 5  ;8
    dec     dx
    jnz     pl_y

    pop     es
    pop     ds
    ret

;************************************************************
;    Random number generator (thx to Binboy!)
;    out: ax = random number (0..255)
;************************************************************

random_num:
    mov     bx, [rnd_seed]
    add     bx, 9248h
    ror     bx, 3
    mov     [rnd_seed], bx
    mov     ax, 255
    mul     bx
    mov     ax, dx
    ret

.data

txt_position   dw  0
txt_wait       dw  0
current_way    dw  offset way_data
current_max    dw  N_OFS
current_col    db  TXT_COLOR
rnd_seed       dw  666h
 
way_data dw   36521,  36201,  35881,  35561,  35241,  34921,  34601,  34281,  33961,  33641,  33321
 dw   33001,  32681,  32361,  32041,  31721,  31401,  31081,  30761,  30441,  30121,  30120
 dw   29800,  29480,  29160,  29159,  28839,  28518,  28198,  28197,  28196,  28515,  28834
 dw   29154,  29474,  29473,  29793,  30112,  30432,  30752,  31072,  31392,  31712,  32032
 dw   32352,  32672,  32992,  33312,  33311,  33631,  33630,  33950,  33949,  33948,  33947
 dw   33946,  33626,  33625,  33305,  32985,  32984,  32664,  32344,  32023,  31703,  31382
 dw   31062,  30742,  30741,  30421,  30420,  30099,  30098,  29777,  29456,  29136,  29135
 dw   29134,  29454,  29774,  30093,  30413,  30733,  31053,  31373,  31693,  32013,  32333
 dw   32653,  32973,  33293,  33613,  33933,  34253,  34573,  34893,  35213,  35533,  35853
 dw   36174,  36494,  36814,  37134,  37135,  31412,  31413,  31093,  31094,  30775,  30776
 dw   30456,  30457,  30458,  30459,  30460,  30461,  30462,  30463,  30464,  30784,  31105
 dw   31425,  31426,  31746,  32066,  32386,  32706,  33026,  33346,  33666,  33986,  34306
 dw   34626,  34946,  35266,  35586,  35905,  36225,  36224,  36544,  36864,  37184,  37183
 dw   34626,  34625,  34945,  34944,  35264,  35263,  35583,  35582,  35902,  35901,  36221
 dw   36220,  36539,  36538,  36858,  36857,  36856,  37176,  37175,  37174,  37173,  37172
 dw   37171,  36851,  36531,  36530,  36210,  35890,  35570,  35250,  34931,  34612,  34292
 dw   34293,  33973,  33654,  33655,  33336,  33017,  33018,  33019,  32699,  32700,  32701
 dw   32702,  32383,  32384,  32385,  28554,  28874,  29194,  29514,  29834,  30154,  30474
 dw   30794,  31114,  31434,  31754,  32074,  32394,  32714,  33034,  33354,  33674,  33675
 dw   33995,  34315,  34635,  34636,  34956,  35276,  35596,  35916,  35917,  36237,  36557
 dw   36877,  36878,  37198,  31750,  31751,  31752,  31753,  31754,  31755,  31435,  31436
 dw   31437,  31438,  31118,  31119,  31120,  31121,  31122,  31448,  31768,  32088,  32408
 dw   32728,  33048,  33368,  33688,  34008,  34328,  34648,  34968,  35288,  35289,  35609
 dw   35929,  35930,  36250,  36570,  36890,  37210,  37211,  37531,  33368,  33048,  32728
 dw   32408,  32409,  32089,  31769,  31770,  31450,  31451,  31452,  31132,  31133,  31134
 dw   31135,  31136,  31137,  31138,  31139,  31460,  31780,  32100,  32420,  32740,  30827
 dw   31147,  31467,  31787,  32107,  32427,  32747,  33067,  33387,  33707,  34028,  34348
 dw   34668,  34988,  34989,  35309,  35629,  35949,  36269,  36589,  36909,  37229,  28907
 dw   28587,  28586,  28906,  29226,  29546,  29866,  29867,  29868,  29548,  29549,  29229
 dw   28909,  28589,  28588,  28587,  30515,  30516,  30836,  30837,  31157,  31477,  31478
 dw   31798,  32119,  32120,  32440,  32760,  32761,  33081,  33082,  33402,  33403,  33723
 dw   33724,  34044,  34045,  34365,  34366,  34686,  34687,  35007,  35008,  35328,  35329
 dw   35649,  35650,  35970,  35971,  29888,  29887,  29886,  30206,  30526,  30846,  30845
 dw   31165,  31485,  31805,  32125,  32124,  32444,  32764,  33083,  33403,  33402,  33722
 dw   34042,  34362,  34682,  34681,  35001,  35321,  35641,  35960,  36280,  36600,  36920
 dw   37240,  26392,  26712,  27033,  27353,  27673,  27993,  27994,  28314,  28634,  28954
 dw   29274,  29594,  29914,  30234,  30554,  30874,  31194,  31514,  31834,  32154,  32474
 dw   32794,  33115,  33435,  33755,  34075,  34395,  34715,  35035,  35036,  35356,  35676
 dw   35996,  36316,  36636,  36956,  36957,  37277,  32795,  32475,  32155,  32156,  31836
 dw   31516,  31517,  31198,  31199,  30879,  30880,  30560,  30561,  30562,  30563,  30564
 dw   30565,  30566,  30567,  30568,  30888,  30889,  31209,  31529,  31849,  32169,  32489
 dw   32809,  33129,  33449,  33769,  34089,  34409,  34729,  34728,  35048,  35368,  35688
 dw   36008,  36328,  36648,  36968,  31216,  31217,  30897,  30898,  30578,  30579,  30260
 dw   30261,  30262,  30263,  30264,  30265,  30266,  30267,  30587,  30907,  30908,  31228
 dw   31548,  31868,  32188,  32508,  32828,  33148,  33149,  33469,  33789,  34109,  34429
 dw   34749,  35069,  35389,  35709,  36029,  36028,  36348,  36668,  36988,  36987,  37307
 dw   37308,  34748,  35068,  35388,  35708,  36028,  36027,  36347,  36667,  36666,  36985
 dw   36984,  37304,  37303,  37302,  37301,  37621,  37620,  37619,  37618,  37298,  36978
 dw   36658,  36338,  36018,  35698,  35378,  35058,  34738,  34739,  34419,  34100,  33780
 dw   33781,  33462,  33463,  33144,  33145,  33146,  33147,  32827,  32828,  31567,  31247
 dw   31246,  30926,  30606,  30605,  30604,  30603,  30602,  30601,  30600,  30599,  30919
 dw   30918,  31238,  31558,  31557,  31877,  32197,  32517,  32837,  33157,  33477,  33478
 dw   33479,  33480,  33481,  33482,  33483,  33484,  33485,  33486,  33487,  33488,  33808
 dw   33809,  34129,  34449,  34450,  34770,  35090,  35410,  35730,  36050,  36370,  36690
 dw   37010,  37330,  37329,  37328,  37648,  37647,  37646,  37645,  37644,  37643,  37642
 dw   37641,  37640,  37320,  37000,  36999,  36678,  36358,  36038,  35718,  35398,  35079
 dw   35080,  35081,  32234,  32555,  32875,  32876,  33196,  33197,  33517,  33518,  33838
 dw   34159,  34160,  34480,  34800,  34801,  35121,  35122,  35442,  35762,  35763,  36083
 dw   30966,  30965,  31285,  31605,  31925,  32245,  32244,  32564,  32884,  33204,  33524
 dw   33844,  34164,  34484,  34804,  35124,  35444,  35764,  36084,  36404,  36724,  37044
 dw   37364,  37684,  38004,  38324,  38644,  38964,  39284,  39283,  39603,  39923,  40243
 dw   40242,  40562,  40882,  41202,  41203,  31613,  31293,  31294,  30974,  30654,  30655
 dw   30656,  30657,  30658,  30659,  30660,  30661,  30662,  30663,  30664,  30984,  31305
 dw   31625,  31945,  32265,  32585,  32905,  33225,  33545,  33865,  34185,  34505,  34825
 dw   35145,  35465,  35785,  36105,  36425,  36745,  37065,  37385,  37384,  37704,  35464
 dw   35144,  35464,  35784,  36104,  36103,  36423,  36422,  36742,  36741,  36740,  37060
 dw   37059,  37379,  37378,  37377,  37376,  37375,  37374,  37054,  36734,  36733,  36413
 dw   36093,  35773,  35453,  35133,  35134,  34814,  34815,  34495,  34496,  34176,  33857
 dw   33858,  33539,  33540,  33220,  33221,  33222,  33223,  33224,  37076,  37075,  37395
 dw   37396,  37397,  37398,  37078,  36758,  36757,  36756,  37076,  36767,  36766,  37086
 dw   37406,  37726,  37727,  37728,  37729,  37730,  37410,  37090,  37089,  37088,  37087
 dw   37100,  37099,  37419,  37739,  37740,  38060,  38061,  38062,  37742,  37422,  37102
 dw   37101,  37100
 
way_data2 dw   25946,  25945,  25944,  25943,  25942,  25941,  25940,  25939,  25938,  25937,  25936
 dw   26256,  26255,  26254,  26573,  26893,  26892,  26891,  27211,  27531,  27530,  27850
 dw   27849,  28169,  28168,  28488,  28807,  29127,  29447,  29767,  29766,  30086,  30406
 dw   30726,  31046,  31366,  31686,  32006,  32326,  32646,  32966,  33287,  33607,  33927
 dw   34247,  34567,  34568,  34888,  35208,  35209,  35529,  35849,  36169,  36170,  36490
 dw   36491,  36811,  31686,  31687,  31688,  31689,  31690,  31691,  31692,  31693,  31694
 dw   31375,  31376,  31377,  31378,  31379,  31059,  31060,  31061,  31062,  30742,  30743
 dw   30744,  32044,  31724,  31404,  31084,  30764,  30763,  30443,  30442,  30441,  30440
 dw   30439,  30438,  30437,  30436,  30756,  30755,  31075,  31395,  31715,  32035,  32355
 dw   32675,  32995,  33315,  33635,  33955,  34275,  34595,  34915,  35235,  35556,  35876
 dw   35557,  35877,  36197,  36517,  36518,  36838,  30432,  30752,  30753,  31073,  31393
 dw   31394,  31714,  32034,  32035,  32355,  32675,  33650,  33651,  33331,  33332,  33333
 dw   33334,  33014,  33015,  33016,  32696,  32697,  32698,  32378,  32379,  32060,  32061
 dw   31741,  31742,  31422,  31102,  30782,  30462,  30142,  30141,  29821,  29820,  29819
 dw   29818,  29817,  29816,  29815,  29814,  30134,  30133,  30453,  30772,  31092,  31412
 dw   31732,  32052,  32372,  32692,  33012,  33332,  33652,  33972,  33973,  34293,  34613
 dw   34933,  34934,  35254,  35255,  35575,  35576,  35577,  35578,  35579,  35580,  35581
 dw   35261,  35262,  34942,  34943,  34623,  34624,  34304,  33984,  33985,  33665,  33671
 dw   33672,  33353,  33354,  33035,  33036,  33037,  32717,  32718,  32719,  32400,  32401
 dw   32081,  32082,  31762,  31763,  31443,  31123,  30803,  30802,  30482,  30481,  30480
 dw   30160,  30159,  30158,  30157,  30156,  30155,  30154,  30474,  30473,  30793,  31113
 dw   31112,  31432,  31752,  32072,  32392,  32712,  33032,  33352,  33672,  33992,  33993
 dw   34313,  34633,  34953,  35273,  35274,  35275,  35595,  35596,  35597,  35598,  35599
 dw   35600,  35601,  35602,  35283,  34963,  34964,  34644,  34645,  34325,  34326,  34006
 dw   34007,  33687,  31465,  31466,  31786,  32106,  32107,  32427,  32428,  32748,  33069
 dw   33070,  33390,  33391,  33711,  33712,  34032,  34033,  34353,  34354,  34674,  34675
 dw   34995,  34996,  35316,  35636,  30198,  30197,  30196,  30516,  30836,  31156,  31475
 dw   31795,  32115,  32435,  32755,  33075,  33395,  33715,  34035,  34355,  34675,  34995
 dw   35315,  35635,  35955,  36275,  36595,  36594,  36914,  37234,  37554,  37874,  38194
 dw   38514,  38834,  39154,  39474,  39794,  40114,  40434,  40754,  41074,  41075,  30856
 dw   30855,  30854,  30853,  30852,  30851,  30850,  31170,  31490,  31489,  31809,  31808
 dw   32128,  32448,  32768,  33088,  33087,  33407,  33727,  33726,  34046,  34366,  34686
 dw   35006,  35326,  35646,  35967,  36287,  36288,  36289,  36609,  36610,  36611,  36612
 dw   36613,  36614,  36615,  36616,  36297,  35978,  35658,  35659,  35339,  35019,  35020
 dw   34700,  34380,  34060,  33740,  33420,  33100,  32780,  32460,  32780,  32460,  32140
 dw   32139,  31819,  31499,  31498,  31178,  31177,  31176,  30856,  30855,  30854,  30229
 dw   30549,  30869,  31189,  31509,  31508,  31828,  32148,  32468,  32788,  33108,  33428
 dw   33748,  34068,  34388,  34708,  35028,  35348,  35668,  35988,  36308,  36309,  36630
 dw   36631,  36632,  36633,  36634,  36635,  36636,  36316,  35997,  35677,  35678,  35358
 dw   35359,  35039,  34719,  34720,  34400,  34080,  33761,  33441,  33122,  32802,  32803
 dw   32483,  32163,  31843,  31523,  31203,  30883,  30563,  30243,  30244,  32482,  32802
 dw   33122,  33442,  33762,  33761,  34081,  34401,  34721,  35041,  35361,  35681,  35682
 dw   35683,  36003,  36323,  36324,  36325,  36977,  36657,  36656,  36336,  36016,  36015
 dw   35695,  35375,  35374,  35054,  34734,  34414,  34094,  33774,  33454,  33134,  32814
 dw   32813,  32493,  32173,  31853,  31533,  31213,  30893,  30573,  33455,  33456,  33136
 dw   32816,  32817,  32497,  32177,  32178,  31858,  31538,  31218,  31219,  31220,  30900
 dw   30901,  30902,  30903,  31224,  31544,  31864,  32184,  36692,  36691,  36371,  36051
 dw   36050,  35730,  35410,  35090,  34770,  34769,  34449,  34129,  33809,  33489,  33169
 dw   33168,  32848,  32528,  32208,  31888,  31568,  31248,  30928,  30608,  30288,  30289
 dw   32849,  32850,  32530,  32210,  32211,  31891,  31892,  31572,  31252,  31253,  30934
 dw   30935,  30935,  30936,  30937,  30938,  30939,  31259,  31260,  31580,  31900,  31901
 dw   32221,  32222,  32542,  32862,  33182,  33502,  33822,  34142,  34462,  34782,  34783
 dw   35103,  35423,  35743,  36063,  31580,  31260,  30940,  30941,  30621,  30622,  30302
 dw   30303,  30304,  29984,  29985,  29986,  29987,  29988,  29989,  29990,  29991,  30311
 dw   30632,  30952,  31272,  31273,  31593,  31913,  32233,  32553,  32873,  33193,  33513
 dw   33834,  34154,  34474,  34794,  35114,  35434,  35754,  36074,  36394,  30962,  31282
 dw   31602,  31922,  32242,  32562,  32882,  33202,  33522,  33842,  33843,  34163,  34483
 dw   34484,  34804,  35124,  35444,  35764,  36084,  36085,  36405,  28402,  28401,  28721
 dw   29041,  29361,  29362,  29363,  29364,  29365,  29045,  29044,  28724,  28723,  28722
 dw   28402,  36416,  36095,  35775,  35455,  35135,  34815,  34495,  34175,  33855,  33534
 dw   33214,  32894,  32893,  32573,  32253,  31933,  31613,  31293,  30973,  30653,  33215
 dw   32895,  32575,  32256,  31936,  31937,  31617,  31297,  31298,  30978,  30979,  30659
 dw   30660,  30661,  30662,  30663,  30664,  30985,  31306,  31626,  31946,  32267,  32587
 dw   32907,  33227,  33547,  33867,  34187,  34507,  34827,  35147,  35467,  35787,  35788
 dw   36108,  36428,  26529,  26849,  27169,  27489,  27809,  28129,  28450,  28770,  29090
 dw   29410,  29730,  30050,  30051,  30371,  30691,  31011,  31331,  31651,  31971,  32291
 dw   32611,  32931,  32932,  33252,  33572,  33573,  33893,  34213,  34533,  34853,  35173
 dw   35493,  35813,  36133,  36134,  36454,  36774,  37094,  30690,  30689,  30688,  30687
 dw   30686,  30685,  30684,  30683,  31003,  31002,  31322,  31641,  31961,  32281,  32601
 dw   32600,  32920,  33240,  33559,  33879,  33878,  34198,  34518,  34838,  35159,  35479
 dw   35480,  35800,  35801,  35802,  35803,  35804,  35805,  35806,  35807,  35808,  35809
 dw   35810,  35811,  35491,  35171,  35172,  34852,  34853,  33584,  33583,  33263,  32943
 dw   32622,  32302,  31982,  31662,  31342,  31343,  31023,  30703,  30383,  30063,  29743
 dw   29423,  29422,  29102,  28782,  28462,  28142,  28141,  27821,  27501,  27502,  27182
 dw   26862,  26542,  26222,  36465,  36464,  36463,  36783,  37103,  37102,  37103,  37423
 dw   37424,  37425,  37426,  37106,  36786,  36466,  36465

.data?

font_address dd ?
frame_cnt    dw ?

let_table    db ((320 * 200) / 8) dup(?)
let_speed    db (320 / 8) dup(?)

end entrypoint
