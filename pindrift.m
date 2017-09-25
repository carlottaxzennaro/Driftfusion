function solstruct = pindrift(varargin);

%%%%%%% REQUIREMENTS %%%%%%%%%%%%
% Requires v2struct toolbox for unpacking parameters structure
% IMPORTANT! Currently uses parameters from pinParams
% ALL VARIABLES MUST BE DECLARED BEFORE UNPACKING STRUCTURE (see below)
% spatial mesh is generated by meshgen_x
% time mesh is generated by meshgen_t

%%%%%%% GENERAL NOTES %%%%%%%%%%%%
% A routine to test solving the diffusion and drift equations using the
% matlab pdepe solver. 
% 
% The solution from the solver is a 3D matrix, u:
% rows = time
% columns = space
% u(1), page 1 = electron density, n
% u(2), page 2 = hole density, p
% u(3), page 3 = mobile defect density, a
% u(4), page 4 = electric potential, V
%
% The solution structure solstruct contains the solution in addition to
% other useful outputs including the parameters sturcture

%%%%% INPUTS ARGUMENTS %%%%%%%
% This version allows a previous solution to be used as the input
% conditions. If there is no input argument asssume default flat background
% condtions. If there is one argument, assume it is the previous solution
% to be used as the initial conditions (IC). If there are two input arguments,
% assume that first is the previous solution, and the
% second is a parameters structure. If the IC sol = 0, default conditions
% are used, but parameters can still be input. If the second argument is
% any character e.g. 'params', then the parameters from the previous solution 
% are used and any changes in the parameters function pinParams are
% ignored.
%  
% AUTHORS
% Piers Barnes last modified (09/01/2016)
% Phil Calado last modified (14/07/2017)

% Graph formatting
set(0,'DefaultLineLinewidth',1);
set(0,'DefaultAxesFontSize',16);
set(0,'DefaultFigurePosition', [600, 400, 450, 300]);
set(0,'DefaultAxesXcolor', [0, 0, 0]);
set(0,'DefaultAxesYcolor', [0, 0, 0]);
set(0,'DefaultAxesZcolor', [0, 0, 0]);
set(0,'DefaultTextColor', [0, 0, 0]);

% Input arguments are dealt with here
if isempty(varargin)

    params = pinParams;      % Calls Function pinParams and stores in sturcture 'params'

elseif length(varargin) == 1
    
    % Call input parameters function
    icsol = varargin{1, 1}.sol;
    icx = varargin{1, 1}.x;
    params = pinParams;

elseif length(varargin) == 2 

    if max(max(max(varargin{1, 1}.sol))) == 0

       params = varargin{2};
    
    elseif isa(varargin{2}, 'char') == 1            % Checks to see if argument is a character
        
        params = varargin{1, 1}.params
        icsol = varargin{1, 1}.sol;
        icx = varargin{1, 1}.x;
    
    else
    
        icsol = varargin{1, 1}.sol;
        icx = varargin{1, 1}.x;
        params = varargin{2};
    
    end

end

% Declare Variables
% The scoping rules for nested and anonymous functions require that all variables
% used within the function be present in the text of the code.
% Rememeber to add new variables here if adding to parameters list- might
% be a better way of doing this.

[BL,BC, Bn ,calcJ, deltax, e, EA,Eg,Ei,Etetl, Ethtl, IP,IC,ilt, Int, JV, JVscan_pnts, N0,NA,ND,NI,PhiA,...
    PhiC,T,Tn,Vapp,Vbi,cn,cp, deltat, edge, Efnside, Efpside,ep,epoints,epp0,eppp,eppi,eppn,...
    et,etln0,etlp0,fastrec,figson,G0, htln0,htlp0, kB,kext, klin, klincon, krad,kradetl, kradhtl,m,mobset,...
    mobseti, mue_p,muh_p, mue_i, muh_i, mue_n, muh_n, mui, ni, ntetl, nthtl,OC, OM, pepe, pedge,...
    pii, pinter, pn, pp, ptetl, pthtl, pulseint, pulselen, pulseon, pulsestart, q,se,sn, sp, side, etlsn, etlsp,...
    htlsn, htlsp, taun_etl, taun_htl, taup_etl, taup_htl, te, ti, tinter, tp, tn, t0,taun,...
    taup,tmax, tmesh_type,tpoints, Vend, Vstart, v, varlist, varstr, wn, wp, wscr, x0,xmax,xmesh_type,...
    xpoints]  = deal(0);

% Unpacks params structure for use in current workspace 
v2struct(params);

% Currently have to repack params since values change after unpacking- unsure as to what's happening there
% Pack parameters in to structure 'params'
varcell = who('*')';                    % Store variables names in cell array
varcell = ['fieldnames', varcell];      % adhere to syntax for v2struct

params = v2struct(varcell);

%%%% Spatial mesh %%%%
if length(varargin) == 0 || length(varargin) == 2 && max(max(max(varargin{1, 1}.sol))) == 0
    
    % Edit meshes in mesh gen
    x = meshgen_x(params);
    
        if OC == 1
        
        % Mirror the mesh for symmetric model - symmetry point is an additional
        % point at device length + 1e-7
        x1 = x;
        x2 = xmax - fliplr(x) + x(end);
        x2 = x2(2:end);                 % Delete initial point to ensure symmetry
        x = [x1, x2];
        
        end
        
    icx = x;
    
else
          
        x = icx;

end

xpoints = length(x);
xmax = x(end);
xnm = x*1e7;        

%%%%%% Time mesh %%%%%%%%%
t = meshgen_t(params);

%%%%%% Generation %%%%%%%%%%
genspace = linspace(0,ti,pii);  %

if OM == 1 && Int ~= 0 %OM = Optical Model
    
    % Beer-Lambert - Currently requires solution in the workspace
    Gx1S = evalin('base', 'BL1Sun');                    % 1 Sun generation profile
    Gx1S = Gx1S';
    GxLas = evalin('base', 'BL638');
    GxLas = GxLas';
   
elseif OM == 2 && Int ~= 0;
    % Call Transfer Matrix code: [Gx1, Gx2] = TMPC1(layers, thicknesses, activeLayer1, activeLayer2)
    [Gx1S, GxLas] = TMPC1({'SiO2', 'TiO2', 'MAPICl', 'Spiro'}, [1e-4 pp 3 pn], 3, 3);
    Gx1S = Gx1S';
    GxLas = GxLas';
  
end

% SOLVER OPTIONS  - limit maximum time step size during integration.
options = odeset('MaxStep',t0/100);
options = odeset('MaxOrder',5);
options = odeset('NonNegative', 1);
options = odeset('NonNegative', 2);
options = odeset('NonNegative', 3);

% Call solver - inputs with '@' are function handles to the subfunctions
% below for the: equation, initial conditions, boundary conditions
sol = pdepe(m,@pdex4pde,@pdex4ic,@pdex4bc,x,t,options);

% --------------------------------------------------------------------------
% Set up partial differential equation (pdepe) (see MATLAB pdepe help for details of c, f, and s)
function [c,f,s,iterations] = pdex4pde(x,t,u,DuDx)

% Open circuit condition- symmetric model
if (OC ==1)
    
    if x > xmax/2

        x = xmax - x;

    end
    
end

%if side == 1
     
% Beer Lambert or Transfer Matrix 1 Sun
if Int ~= 0 && OM ==1 || Int ~= 0 && OM == 2
     
      if x > tp && x < (tp+ti) 
          g = Int*interp1(genspace, Gx1S, (x-tp));
      else
          g = 0;
      end
 
    % Add pulse
    if pulseon == 1
        if  t >= 10e-6 && t < pulselen + 10e-6
           if x > tp && x < (tp+ti)
                lasg = pulseint*interp1(genspace, GxLas, (x-tp));
                g = g + lasg;
           end
        end
    end
  
% Uniform Generation
elseif OM == 0
      
      if Int ~= 0 && x > tp && x < (tp+ti)    
           g = Int*G0;
      else
           g = 0;
      end
        
        % Add pulse
        if pulseon == 1
            if  t >= pulsestart && t < pulselen + pulsestart
                
                g = g+(pulseint*1e21);
            
            end
        end
        
else
        g = 0;
        
end

% Prefactors set to 1 for time dependent components - can add other
% functions if you want to include the multiple trapping model
c = [1
     1
     1
     0];

% p-type
if x < tp
    
 f = [(mue_p*(u(1)*-DuDx(4)+kB*T*DuDx(1)));
     (muh_p*(u(2)*DuDx(4)+kB*T*DuDx(2)));     
     0;
     DuDx(4);];                                  

 s = [ - kradhtl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+pthtl)) + (taup_htl*(u(1)+nthtl)))); %- klincon*min((u(1)- htln0), (u(2)- htlp0)); % 
       - kradhtl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+pthtl)) + (taup_htl*(u(1)+nthtl)))); %- kradhtl*((u(1)*u(2))-(ni^2)); %- klincon*min((u(1)- htln0), (u(2)- htlp0)); % - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+pthtl)) + (taup_htl*(u(1)+nthtl))));
      0;
      (q/eppp)*(-u(1)+u(2)+u(3)-NI-NA);];%+pthtl-nthtl);];

% % p-type/perovskite interface
% elseif x > tp - te && x <= tp
% 
%        f = [(mue_p*(u(1)*-DuDx(4)+kB*T*DuDx(1)));
%      (muh_p*(u(2)*DuDx(4)+kB*T*DuDx(2)));     
%      0;
%      DuDx(4);];                                  
% 
%  s = [- kradhtl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+pthtl)) + (taup_htl*(u(1)+nthtl))));
%       - kradhtl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+pthtl)) + (taup_htl*(u(1)+nthtl))));
%       0;
%       (q/eppp)*(-u(1)+u(2)-NA+pthtl-nthtl);];
 
% Intrinsic
elseif x >= tp && x <= tp + ti
    
   f = [(mue_i*(u(1)*-DuDx(4)+kB*T*DuDx(1)));       % Current terms for electrons
     (muh_i*(u(2)*DuDx(4)+kB*T*DuDx(2)));           % Current terms for holes
     (mui*(u(3)*DuDx(4)+kB*T*DuDx(3)));             % Current terms for ions
     DuDx(4);];                                     % Electric field

 s = [g - krad*((u(1)*u(2))-(ni^2)); % - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+pthtl)) + (taup_htl*(u(1)+nthtl)))); %- krad*((u(1)*u(2))-(ni^2));  % - klin*min((u(1)- ni), (u(2)- ni)); % - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+ptrap)) + (taup_htl*(u(1)+ntrap))));
      g - krad*((u(1)*u(2))-(ni^2)); % - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+pthtl)) + (taup_htl*(u(1)+nthtl)))); %- krad*((u(1)*u(2))-(ni^2));  % - klin*min((u(1)- ni), (u(2)- ni)); % - (((u(1)*u(2))-ni^2)/((taun_htl*(u(2)+ptrap)) + (taup_htl*(u(1)+ntrap))));
      0;
      (q/eppi)*(-u(1)+u(2)+u(3)-NI);]; 

% % perovskite/n-type interface  
% elseif x >= tp + ti && x < tp + ti + te
%     
%      f = [(mue_n*(u(1)*-DuDx(4)+kB*T*DuDx(1)));
%      (muh_n*(u(2)*DuDx(4)+kB*T*DuDx(2)));      
%      0;
%      DuDx(4)];                                      
% 
%  s = [- kradetl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_etl*(u(2)+ptetl)) + (taup_etl*(u(1)+ntetl))));
%       - kradetl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_etl*(u(2)+ptetl)) + (taup_etl*(u(1)+ntetl))));
%       0;
%       (q/eppn)*(-u(1)+u(2)+ND+ptetl-ntetl)];


% n-type
elseif x > tp + ti && x <= xmax
  
 f = [(mue_n*(u(1)*-DuDx(4)+kB*T*DuDx(1)));
     (muh_n*(u(2)*DuDx(4)+kB*T*DuDx(2)));      
     0;
     DuDx(4)];                                      

s = [ - kradetl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_etl*(u(2)+ptetl)) + (taup_etl*(u(1)+ntetl))));   %- kradetl*((u(1)*u(2))-(ni^2)); %- klincon*min((u(1)- etln0), (u(2)- etlp0)); %  - (((u(1)*u(2))-ni^2)/((taun_etl*(u(2)+ptetl)) + (taup_etl*(u(1)+ntetl))));
      - kradetl*((u(1)*u(2))-(ni^2)) - (((u(1)*u(2))-ni^2)/((taun_etl*(u(2)+ptetl)) + (taup_etl*(u(1)+ntetl))));   %- kradetl*((u(1)*u(2))-(ni^2)); % - klincon*min((u(1)- etln0), (u(2)- etlp0)); %- (((u(1)*u(2))-ni^2)/((taun_etl*(u(2)+ptetl)) + (taup_etl*(u(1)+ntetl))));
      0;
      (q/eppn)*(-u(1)+u(2)+u(3)-NI+ND);];%+ptetl-ntetl)];
      
end

end

% --------------------------------------------------------------------------

% Define initial conditions.
function u0 = pdex4ic(x)

% Open circuit condition- symmetric model
if (OC ==1)
    
    if x >= xmax/2

        x = xmax - x;

    end
    
end

if length(varargin) == 0 || length(varargin) >= 1 && max(max(max(varargin{1, 1}.sol))) == 0
    
    % p-type
    if x < (tp - wp)
    
       u0 = [htln0;
             htlp0;
              NI;
              0];  

    % p-type SCR    
    elseif  x >= (tp - wp) && x < tp

        u0 = [N0*exp(q*(Efnside + EA + q*((((q*NA)/(2*eppi))*(x-tp+wp)^2)))/(kB*T));                            %ni*exp((Efnside - (-q*((((q*NA)/(2*eppp))*(x-tp+wp)^2))))/(kB*T));
              N0*exp(-q*(q*((((q*NA)/(2*eppi))*(x-tp+wp)^2)) + EA + Eg + Efpside)/(kB*T)) ;
              NI;
              (((q*NA)/(2*eppi))*(x-tp+wp)^2)];

    % Intrinsic

    elseif x >= tp && x <= tp+ ti

        u0 =  [N0*exp(q*(Efnside + EA + q*(((x - tp)*((1/ti)*(Vbi - ((q*NA*wp^2)/(2*eppi)) - ((q*ND*wn^2)/(2*eppi))))) + ((q*NA*wp^2)/(2*eppi))))/(kB*T));
                N0*exp(-q*(q*(((x - tp)*((1/ti)*(Vbi - ((q*NA*wp^2)/(2*eppi)) - ((q*ND*wn^2)/(2*eppi))))) + ((q*NA*wp^2)/(2*eppi))) + EA + Eg + Efpside)/(kB*T)) ;
                NI;
                ((x - tp)*((1/ti)*(Vbi - ((q*NA*wp^2)/(2*eppi)) - ((q*ND*wn^2)/(2*eppi))))) + ((q*NA*wp^2)/(2*eppi)) ;];

    % n-type SCR    
    elseif  x > (tp+ti) && x <= (tp + ti + wn)

        u0 = [N0*exp(q*(Efnside + EA + q*((((-(q*ND)/(2*eppi))*(x-ti-tp-wn)^2) + Vbi)))/(kB*T));
              N0*exp(-q*(q*((((-(q*ND)/(2*eppi))*(x-ti-tp-wn)^2) + Vbi)) + EA + Eg + Efpside)/(kB*T));
              NI;
              (((-(q*ND)/(2*eppi))*(x-tp - ti -wn)^2) + Vbi)]; 

    % n-type
    elseif x > (tp + ti + wn) && x <= xmax

         u0 = [etln0;
               etlp0;
               NI;
               Vbi];
    end      
    %}
     
elseif length(varargin) == 1 || length(varargin) >= 1 && max(max(max(varargin{1, 1}.sol))) ~= 0
    % insert previous solution and interpolate the x points
    u0 = [interp1(icx,icsol(end,:,1),x)
          interp1(icx,icsol(end,:,2),x)
          interp1(icx,icsol(end,:,3),x)
          interp1(icx,icsol(end,:,4),x)];

end

end

% --------------------------------------------------------------------------

% Define boundary condtions, refer pdepe help for the precise meaning of p
% and you l and r refer to left and right.
% in this example I am controlling the flux through the boundaries using
% the difference in concentration from equilibrium and the extraction
% coefficient.
function [pl,ql,pr,qr] = pdex4bc(xl,ul,xr,ur,t)

if JV == 1;
        
    Vapp = Vstart + ((Vend-Vstart)*t*(1/tmax));
    
end

% Open circuit condition- symmetric model
if OC == 1
      
    pl = [0;
          0;
          0;
          -ul(4)];

    ql = [1; 
          1;
          1;
          0];

    pr = [0;
          0;
          0;
          -ur(4)];  

    qr = [1; 
          1;
          1;
          0];

else
    
    % Zero current
    if BC == 0
        
        pl = [0;
            0;
            0;
            -ul(4)];
        
        ql = [1;
            1;
            1;
            0];
        
        pr = [0;
            0;
            0;
            -ur(4) + Vbi - Vapp;];
        
        qr = [1;
            1;
            1;
            0];
        
    % Fixed charge at the boundaries- contact in equilibrium with etl and htl
    % Blocking electrode
    elseif BC == 1
        
        pl = [0;
            (ul(2)-htlp0);
            0;
            -ul(4);];
        
        ql = [1;
            0;
            1;
            0];
        
        pr = [(ur(1)-etln0);
            0;
            0;
            -ur(4)+Vbi-Vapp;];
        
        qr = [0;
            1;
            1;
            0];
        
        % Non- selective contacts - equivalent to infinite surface recombination
        % velocity for minority carriers
    elseif BC == 2
        
        pl = [ul(1) - htln0;
            ul(2) - htlp0;
            0;
            -ul(4);];
        
        ql = [0;
            0;
            1;
            0];
        
        pr = [ur(1) - etln0;
            ur(2) - etlp0;
            0;
            -ur(4)+Vbi-Vapp;];
        
        qr = [0;
            0;
            1;
            0];
    
    end
end

end


%%%%% Analysis %%%%%

% split the solution into its component parts (e.g. electrons, holes and efield)
n = sol(:,:,1);
p = sol(:,:,2);
a = sol(:,:,3);
V = sol(:,:,4);

% Calculate energy levels and chemical potential         
V = V - EA;                                % Electric potential
Ecb = EA-V-EA;                             % Conduction band potential
Evb = IP-V-EA;                             % Valence band potential
Efn = real(-V+Ei+(kB*T/q)*log(n/ni));      % Electron quasi-Fermi level 
Efp = real(-V+Ei-(kB*T/q)*log(p/ni));      % Hole quasi-Fermi level
Phin = real(Ei+(kB*T/q)*log(n/ni)-EA);     % Chemical Potential electron
Phip = real(Ei-(kB*T/q)*log(p/ni)-EA);
Phi = Phin - Phip;

% p-type binary matrix
pBM = ones(length(t), xpoints)*diag(x < tp);
% Intrinsic binary matrix
iBM = ones(length(t), xpoints)*diag(x >= tp & x <= (tp + ti));
% n-type binary matrix
nBM = ones(length(t), xpoints)*diag(x > tp + ti);

nstat = zeros(1, xpoints);                                  % Static charge array
nstat = (-NA-NI)*pBM + (-NI*iBM) + (ND-NI)*nBM; %(-NA+pthtl-nthtl-NI)*pBM + (-NI*iBM) + (ND+ptetl-ntetl-NI)*nBM;   
rhoc = (-n + p + a + nstat);     % Net charge density calculated from adding individual charge densities

% Remove static ionic charge from contacts for plotting
a = a - (NI*pBM + NI*nBM);

% Recomination Rate - NEEDS SORTING 24/03/2016
Urec = 0;% (krad((n*p)-ni^2) + sn*(n-htln0)).*nBM + (krad((n*p)-ni^2)+ sp*(p-etlp0)).*pBM;

if OC == 1
    
    Voc = Efn(:, round(xpoints/2)) - Efp(:, 1);                    % Open Circuit Voltage
    Voc_chem = Phin(:, round(xpoints/2)) - Phip(:, 1);              % Chemical componenet
    Voc_V = V(:, round(xpoints/2)) - V(:, 1);
    
end

% TPV
if OC == 1  && pulseon == 1                 % AC coupled mode
   
    Voc = Voc - Voc(1, :);                  % Removes baseline from TPV
    t = (t-(pulsestart+pulselen));          % Zero point adjustment                               
end

% TPC
if OC == 0 && pulseon == 1 

    t = (t-pulsestart);                     % TPC Zero point adjustment   

end

for i=1:length(t)

    Fp(i,:) = -gradient(V(i, :), x);       % Electric field calculated from V

end

Potp = V(end, :);

rhoctot = trapz(x, rhoc, 2)/xmax;   % Net charge

rho_a = a - NI;                  % Net ionic charge
rho_a_tot = trapz(x, rho_a, 2)/xmax;   % Total Net ion charge

ntot = trapz(x, n, 2);     % Total 
ptot = trapz(x, p, 2);

if JV == 1
    
    Vapp_arr = Vstart + ((Vend-Vstart)*t*(1/tmax));
    
end

% Calculates current at every point and all times
if calcJ == 1

% find the internal current density in the device
Jndiff = zeros(length(t), length(x));
Jndrift = zeros(length(t), length(x));
Jpdiff = zeros(length(t), length(x));
Jpdrift= zeros(length(t), length(x));
Jpart = zeros(length(t), length(x));
Jtot = zeros(length(t));   
    
for j=1:length(t)
    
    tj = t(j);
    
    [nloc,dnlocdx] = pdeval(0,x,n(j,:),x);    
    [ploc,dplocdx] = pdeval(0,x,p(j,:),x);
    [iloc,dilocdx] = pdeval(0,x,a(j,:),x);
    [Vloc, Floc] = pdeval(0,x,V(j,:),x);
    
    % Particle currents
    Jndiff(j,:) = (mue_i*kB*T*dnlocdx)*(1000*e);
    Jndrift(j,:) = (-mue_i*nloc.*Floc)*(1000*e);
   
    Jpdiff(j,:) = (-muh_i*kB*T*dplocdx)*(1000*e);
    Jpdrift(j,:) = (-muh_i*ploc.*Floc)*(1000*e);
    
    Jidiff(j,:) = (-mui*kB*T*dilocdx)*(1000*e);
    Jidrift(j,:) = (-mui*iloc.*Floc)*(1000*e);

    % Particle current
    Jpart(j,:) = Jndiff(j,:) + Jndrift(j,:) + Jpdiff(j,:) + Jpdrift(j,:) + Jidiff(j,:) + Jidrift(j,:);   
    
    % Electric Field
    Floct(j,:) = Floc;
    
end

% Currents at the boundaries (should be the same)
Jpartl = Jpart(:,1)
Jpartr = Jpart(:,round(xpoints/2))

% Displacement Current at right hand side
Fend = (Floct(:, end));
Jdispr = -(e*1000)*eppn*gradient(Floct(:, end), t);

Jtotr = Jpartr + Jdispr;    

end

% Calculates currents only for right hand x points at all times
if calcJ == 2
    
    % find the internal current density in the device
    Jndiff = zeros(length(t), 1);
    Jndrift = zeros(length(t), 1);
    Jpdiff = zeros(length(t), 1);
    Jpdrift= zeros(length(t), 1);
    Jpart = zeros(length(t), 1);

        for j=1:length(t)

            [nloc,dnlocdx] = pdeval(0,x,n(j,:),x(round(xpoints/2)));    
            [ploc,dplocdx] = pdeval(0,x,p(j,:),x(round(xpoints/2)));
            [iloc,dilocdx] = pdeval(0,x,a(j,:),x(round(xpoints/2)));
            [Vloc, Floc] = pdeval(0,x,V(j,:),x(round(xpoints/2)));

            % Particle currents
            Jndiff(j) = (mue_n*kB*T*dnlocdx)*(1000*e);
            Jndrift(j) = (-mue_n*nloc.*Floc)*(1000*e);

            Jpdiff(j) = (-muh_n*kB*T*dplocdx)*(1000*e);
            Jpdrift(j) = (-muh_n*ploc.*Floc)*(1000*e);

            Jidiff(j) = (-mui*kB*T*dilocdx)*(1000*e);
            Jidrift(j) = (-mui*iloc.*Floc)*(1000*e);

            % Particle current
            Jpart(j) = Jndiff(j) + Jndrift(j) + Jpdiff(j) + Jpdrift(j) + Jidiff(j) + Jidrift(j);   

            % Electric Field
            Floct(j) = Floc;

        end

    % Currents at the boundaries
    Jpartr = Jpart';

    %Jpartr = -(sn*n(:, end) - ni) %Check when surface recombination is used

    % Displacement Current at right hand side

    Jdispr = (e*1000)*eppn*gradient(Floct, t);

    Jtotr = Jpartr + Jdispr;     

    if pulseon == 1

        Jtotr = Jtotr - Jtotr(end);    % remove baseline

    end

end

% Current calculated from QFL
if calcJ == 3

        for j=1:length(t)

            dEfndx(j,:) = gradient(Efn(j, :), x);
            dEfpdx(j,:) = gradient(Efp(j, :), x);

            [Vloc, Floc] = pdeval(0,x,V(j,:),x(end));
             % Electric Field
            Floct(j) = Floc;

        end

    Jpart =  mue_i*n.*dEfndx*(1000*e) +  muh_i*p.*dEfpdx*(1000*e);

    Jdispr = (e*1000)*eppn*gradient(Floct, t);
    Jpartr = Jpart(:,pe+0.2*pp);
    Jtotr = Jpartr + Jdispr;
    Jdispr = 0;

end

%%%%% GRAPHING %%%%%%%%

%Figures
if figson == 1;
    
    % Open circuit voltage
      if OC == 1
        
        figure(7);
        plot (t, Voc);
        xlabel('Time [s]');   
        ylabel('Voltage [V]');

      end

% Defines end points for the graphing
if OC == 1
    
    xnmend = round(xnm(end)/2);
    
else
    
    xnmend = xnm(end);
end

% Band Diagram
FH1 = figure(1)
%set(FigHandle, 'units','normalized','position',[.1 .1 .4 .4]);
PH1 = subplot(3,1,1)
plot (xnm, Efn(end,:), '--', xnm, Efp(end,:), '--', xnm, Ecb(end, :), xnm, Evb(end ,:));
%legend('E_{fn}', 'E_{fp}', 'CB', 'VB');
set(legend,'FontSize',12);
%xlabel('Position [nm]');
ylabel('Energy [eV]'); 
xlim([0, xnmend]);
ylim([-3, 0.5]);
set(legend,'FontSize',12);
set(legend,'EdgeColor',[1 1 1]);
grid off;

% Electronic Charge Densities
PH2 = subplot(3,1,2);
semilogy(xnm, (sol(end,:,1)), xnm, (sol(end,:,2)));
ylabel('{\itn, p} [cm^{-3}]')
legend('\itn', '\itp')
%xlabel('Position [nm]')
xlim([0, xnmend]);
ylim([1e0, 1e20]);
set(legend,'FontSize',12);
set(legend,'EdgeColor',[1 1 1]);
grid off

% Ionic charge density
PH3 = subplot(3,1,3)
plot(xnm, a(end,:)/1e19, 'black');
ylabel('{\ita} [x10^{19} cm^{-3}]')
xlabel('Position [nm]')
xlim([0, xnmend]);
ylim([0, 1.1*(max(sol(end,:,3))/1e19)]);
set(legend,'FontSize',12);
set(legend,'EdgeColor',[1 1 1]);
grid off

%{
% Ion charge
figure(3)
%set(FigHandle, 'units','normalized','position',[.1 .1 .4 .4]);
plot(xnm, Irho (end,:))
legend('Ions')
set(legend,'FontSize',16);
xlabel('Position [nm]');
ylabel('Density [cm^{-3}]');
xlim([0, xnmend]);
set(legend,'FontSize',14);
set(legend,'EdgeColor',[1 1 1]);
grid off;
drawnow;

figure(4);
surf(x,t,V);
title('Electric Potential (x,t)');
xlabel('Distance x');
ylabel('time');
%}

% Net charge
figure(5)
plot(xnm, rhoc(end, :))
ylabel('Net Charge Density [cm^{-3}]')
xlabel('Position [nm]')
xlim([0, xnmend]);
set(legend,'FontSize',14);
set(legend,'EdgeColor',[1 1 1]);
grid off
%{

figure(6)
plot(t, ntot, t, ptot)
ylabel('Charge Density [cm^{-3}]')
xlabel('time [s]')
legend('electrons', 'holes')
set(legend,'FontSize',14);
set(legend,'EdgeColor',[1 1 1]);
grid off
%}

if OM == 1 && Int~=0 || OM == 2 && Int~=0

    genspacenm = genspace * 1e7;

    figure(7);
    plot(genspacenm, Gx1S, genspacenm, GxLas)
    ylabel('Generation Rate [cm^{3}s^{-1}]');
    xlabel('Position [nm]');
    legend('1 Sun', '638 nm');
    xlim([0, genspacenm(end)]);
    grid off

end

if calcJ == 1

    figure(8);
    plot(xnm,Jndiff(end, :),xnm,Jndrift(end, :),xnm,Jpdiff(end, :),xnm,Jpdrift(end, :),xnm,Jidiff(end, :),xnm,Jidrift(end, :),xnm,Jpart(end, :));
    legend('Jn diff','Jn drift','Jp diff','Jp drift','Ji diff','Ji drift','Total J');
    xlabel('Position [nm]');
    ylabel('Current Density [mA cm^-2]');
    set(legend,'FontSize',12);
    set(legend,'EdgeColor',[1 1 1]);
    xlim([0, xnmend]);
    grid off;
    drawnow;

%{
% Electric Field
figure(9);
surf(xnm, t, Floct);
xlabel('Position [m]');
ylabel('time [s]');
title('Electric Field');
%}

end

if calcJ == 1 || calcJ == 2 || calcJ == 3

% Particle and displacement currents as a function of time
figure(10);
plot(t, Jtotr, t, Jpartr, t, Jdispr);
legend('Jtotal', 'Jparticle', 'Jdisp')
xlabel('time [s]');
ylabel('J [mA cm^{-2}]');
set(legend,'FontSize',16);
set(legend,'EdgeColor',[1 1 1]);
grid off;
drawnow;

    if JV == 1
        %JV
        figure(11)
        plot(Vapp_arr, Jtotr)
        xlabel('V_{app} [V]')
        ylabel('Current Density [mA cm^-2]');
        grid off;
    end

end

drawnow

end


%--------------------------------------------------------------------------------------

% Readout solutions to structure
solstruct.sol = sol; solstruct.n = n(end, :)'; solstruct.p = p(end, :)'; solstruct.a = a(end, :)';...
solstruct.V = V(end, :)'; solstruct.x = x; solstruct.t = t; solstruct.Urec = Urec; 
solstruct.Ecb = Ecb(end, :)'; solstruct.Evb = Evb(end, :)'; solstruct.Efn = Efn(end, :)'; solstruct.Efp = Efp(end, :)';...
solstruct.xnm = xnm';

if OC == 1
    
    solstruct.Voc = Voc;
    solstruct.Voc_chem = Voc_chem;
    solstruct.Voc_V = Voc_V;
end

if calcJ ~= 0

solstruct.Jtotr = Jtotr; solstruct.Jpartr = Jpartr; solstruct.Jdispr = Jdispr,  

end

if length(varargin) == 0 || length(varargin) == 2 && max(max(max(varargin{1, 1}.sol))) == 0
    
    params = rmfield(params, 'params');
    params = rmfield(params, 'varargin');
    
else
    
    params = rmfield(params, 'icsol');
    params = rmfield(params, 'icx');  
    params = rmfield(params, 'params');
    params = rmfield(params, 'varargin');
    
end
% Store params
solstruct.params = params;        

if (OC ==0)
    
    assignin('base', 'sol', solstruct)

elseif (OC ==1)
    
    assignin('base', 'ssol', solstruct)

end




end


%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Unused figures

%{
figure(1);
surf(x,t,n);
set(gca, 'ZScale', 'log')
%semilogy(x,n(end,:));
title('n(x,t)');
xlabel('Distance x');
ylabel('time');

figure(2);
surf(x,t,p);
set(gca, 'ZScale', 'log')
title('p(x,t)');
xlabel('Distance x');
ylabel('time');

figure(3);
surf(x,t,a);
title('ion(x,t)');
xlabel('Distance x');
ylabel('time');

figure(11)
plot(xnm, Fc, xnm, Fp);
xlim([0, (xnmend/2)]);
legend('from charge', 'from pot')
ylabel('E Field [V/cm]');
grid off;

% Electric Field vs Position
figure(6);
plot(xnm, Fp(end, :));
xlabel('Position [nm]');
ylabel('Electric Field [Vcm^{-1}]');
grid off;

%}

%{
figure(3)
%set(FigHandle, 'units','normalized','position',[.1 .1 .4 .4]);
[Ax1, h1, h2] = plotyy(xnm, rhoc(end, :), xnm, Urec(end, :));
linkaxes(Ax1,'x');
set(gca,'xlim',[0, (xnmend/2)]);
ylabel(Ax1(1),'Net Charge Density [cm^{-3}]') % left y-axis
ylabel(Ax1(2),{'Recombination';'Rate [cm^{-3}s^{-1}]'}) % right y-axis
%set(Ax1(2),'YScale','log')
set(Ax1(1),'Position', [0.1 0.11 0.7 0.8]);
set(Ax1(2),'Position', [0.1 0.11 0.7 0.8]);
set(Ax1(1),'ycolor',[0.1, 0.1, 0.1]) 
set(Ax1(2),'ycolor',[0, 0.4470, 0.7410])
set(h1,'color',[0.1, 0.1, 0.1])
set(h2, 'color',[0, 0.4470, 0.7410])
grid off;

figure(4)
plot(xnm, g);
grid off

% Electric and Checmial Potential components
figure(4)
%set(FigHandle, 'units','normalized','position',[.1 .1 .4 .4]);
[Ax2, h3, h4] = plotyy(xnm, Potp, xnm, Phi(end,:));
linkaxes(Ax2,'x');
set(gca,'xlim',[0, (xnmend/2)]);
ylabel(Ax2(1),'Electric Potential [V]') % left y-axis
ylabel(Ax2(2),'Chemical Potential [V]') % right y-axis
% get current (active) axes property
set(Ax2(1),'Position', [0.13 0.11 0.775-.08 0.815]);
set(Ax2(2),'Position', [0.13 0.11 0.775-.08 0.815]);
set(Ax2(1),'ycolor',[0.1, 0.1, 0.1]) 
set(Ax2(2),'ycolor',[0.8500, 0.3250, 0.0980])
set(h3,'color',[0.1, 0.1, 0.1])
grid off;



% figure(200)
% [AX,H1,H2] = plotyy(xnm, [Jidiff(end, :).', Jidrift(end, :).'], xnm, (sol(end,:,3)));
% legend('Ion diffusion', 'Ion drift', 'a')
% xlabel('Position [nm]');
% ylabel('Density [cm^{-3}]/Current Density');
% set(AX(2),'Yscale','linear');
% set(legend,'FontSize',20);
% set(legend,'EdgeColor',[1 1 1]);
% set(AX(1), 'Position',[0.18 0.18 0.7 0.70]);     % left, bottom, width, height       
% set(AX(2), 'Position',[0.18 0.18 0.7 0.70]);
% box on
% set(AX(1), 'YMinorTick','on');     % left, bottom, width, height       
% set(AX(2), 'XMinorTick','on','YMinorTick','on');
% set(AX(1),'xlim',[190 250]);
% set(AX(2),'xlim',[190 250]);
% %set(AX(1),'ylim',[1e6 1e18]);
% set(AX(2),'ycolor',[0.9290    0.6940    0.1250]);
% set(H2,'color',[0.9290    0.6940    0.1250]);
% set(legend,'FontSize',12);
% set(legend,'EdgeColor',[1 1 1]);
% grid off;

%}


