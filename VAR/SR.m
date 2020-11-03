function SRout = SR(VAR,SIGN,VARopt)
% =========================================================================
% Compute IRs, VDs, and HDs for a VAR model estimated with VARmodel and 
% identified with sign restrictions
% =========================================================================
% SRout = SR(VAR,R,VARopt)
% -------------------------------------------------------------------------
% INPUT
%   - VAR: structure, result of VARmodel function
%   - R: 3-D matrix containing the sign restrictions (nvar,3,nshocks)
%       described below
%   - VARopt: options of the VAR (see VARoption from VARmodel)
% -------------------------------------------------------------------------
% OUTPUT
%   - SRout
%       * IRall : 4-D matrix of IRs  (nsteps,nvar,nshocks,ndraws)
%       * IRmed : median of IRall
%       * IRinf : lower bound of IRall
%       * IRsup : upper bound of IRall
% 
%       * VDall : 4-D matrix of VDs (nsteps,nvar,nshocks,ndraws)
%       * VDmed : median of VDall
%       * VDinf : lower bopund of VDall
%       * VDsup : upper bopund of VDall
% 
%       * Ball  : 4-D matrix of Bs (nvar,nvar,nshocks,ndraws)
%       * Bmed  : median of Ball
%       * Binf  : lower bound of Ball
%       * Bsup  : upper bound of Ball
% 
%       * HDmed : structure with median of HDall (not reported)
%       * HDinf : structure with lower bound of HDall (not reported)
%       * HDsup : structure with upper bound of HDall (not reported)
% =========================================================================
% VAR Toolbox 3.0
% Ambrogio Cesa Bianchi, March 2020
% ambrogio.cesabianchi@gmail.com
% -------------------------------------------------------------------------
% Notes:
% -----
% This code follows the notation as in the lecture notes available at
% https://sites.google.com/site/ambropo/MatlabCodes
% -----
% The SIGN matrix has dimension (nvar,nshocks). Assume you have three 
% variables and you want to identify just one shock, which has positive
% impact on the first variable, negative impact on the second variable, and 
% and unrestricted impact on the third variable. The the SIGN matrix 
% should be specified as:
% 
%             shock1      shock2     shock3
%  SIGN = [     1           0           0          % VAR1
%              -1           0           0          % VAR2
%              -1           0           0];        % VAR3
% 
% That is: the first column defines the signs of the response of the three 
% variables to the first shock.
% -----


%% Check inputs
%==========================================================================
if ~exist('SIGN','var')
    error('You have not provided sign restrictions (SIGN)')
end

if ~exist('VARopt','var')
    error('You need to provide VAR options (VARopt from VARmodel)');
end


%% Retrieve parameters and preallocate variables
%==========================================================================
nvar    = VAR.nvar;
nvar_ex = VAR.nvar_ex;
nsteps  = VARopt.nsteps;
ndraws  = VARopt.ndraws;
nobs    = VAR.nobs;
nlag    = VAR.nlag;
pctg    = VARopt.pctg;

% Initialize empty matrix for the IR draws
IRall  = nan(nsteps,nvar,nvar,ndraws); 
VDall = nan(nsteps,nvar,nvar,ndraws); 
HDall.shock  = zeros(nobs+nlag,nvar,nvar,ndraws); 
HDall.init   = zeros(nobs+nlag,nvar,ndraws); 
HDall.const  = zeros(nobs+nlag,nvar,ndraws); 
HDall.trend  = zeros(nobs+nlag,nvar,ndraws); 
HDall.trend2 = zeros(nobs+nlag,nvar,ndraws); 
HDall.endo   = zeros(nobs+nlag,nvar,ndraws); 
HDall.exo    = zeros(nobs+nlag,nvar,nvar_ex,ndraws);
Ball = nan(nvar,nvar,ndraws); 


%% Sign restriction routine
%==========================================================================
jj = 0; % accepted draws
ww = 1; % index for printing on screen
while jj < ndraws

    % Set up VAR_draw.(label{1}) for rotations: Only identification uncertainty
    label  = {['draw' num2str(jj)]};
    VAR_draw.(label{1}) = VAR;
    VARopt.ident = 'sr';
    % If selected, set up VAR_draw.(label{1}) to consider identification + model uncertainty
    if VARopt.sr_mod==1 
        % Draw F and sigma from the posterior and 
        [sigma_draw, Ft_draw] = VARdrawpost(VAR);
        VAR_draw.(label{1}).Ft = Ft_draw;
        VAR_draw.(label{1}).sigma = sigma_draw;
    end
    
    % Compute rotated B matrix
    B = SignRestrictions(SIGN,VAR_draw.(label{1}),VARopt); 
    
    % Note: e = (inv(B)*VAR_draw.(label{1}).resid')';
    % Check orthogonality:
    % corr((inv(B)*VAR_draw.(label{1}).resid')')
    
    % Store B
    jj = jj+1;
    Ball(:,:,jj) = B;
    
    % Update VAR_draw.(label{1}) with the rotated B matrix for IR, VD, and HD
    VAR_draw.(label{1}).B = B; 

    % Compute and store IR, VD, HD
    [aux_irf, VAR_draw.(label{1})] = VARir(VAR_draw.(label{1}),VARopt); 
    IRall(:,:,:,jj)  = aux_irf;
    aux_fevd = VARvd(VAR_draw.(label{1}),VARopt);
    VDall(:,:,:,jj)  = aux_fevd;
    aux_hd = VARhd(VAR_draw.(label{1}),VARopt);
    HDall.shock(:,:,:,jj) = aux_hd.shock;
    HDall.init(:,:,jj)    = aux_hd.init;
    HDall.const(:,:,jj)   = aux_hd.const;
    HDall.trend(:,:,jj)   = aux_hd.trend;
    HDall.trend2(:,:,jj)  = aux_hd.trend2;
    HDall.endo(:,:,jj)    = aux_hd.endo;
    if nvar_ex>0; HDall.exo(:,:,:,jj) = aux_hd.exo; end

    % Display number of loops
    if jj==VARopt.mult*ww
        disp(['Rotation: ' num2str(jj) ' / ' num2str(ndraws)]);
        ww=ww+1;
    end

end
disp('-- Done!');
disp(' ');


%% Store results
%==========================================================================
% Store all accepted IRs and VDs
SRout.IRall = IRall;
SRout.VDall = VDall;
SRout.Ball  = Ball;
SRout.HDall = HDall;

% Compute and save median B matrix
SRout.Bmed = median(Ball,3);

% Compute and save true B matrix that is closer to median
aux = sum(sum((Ball-SRout.Bmed).^2,1),2);
sel = find(aux==min(aux));
sel = sel(1);
SRout.B = Ball(:,:,sel);

% Compute IR and VD based on all rotations
pctg_inf = (100-pctg)/2; 
pctg_sup = 100 - (100-pctg)/2;
SRout.IRmed = median(IRall,4);
aux = prctile(IRall,[pctg_inf pctg_sup],4);
SRout.IRinf = aux(:,:,:,1);
SRout.IRsup = aux(:,:,:,2);
SRout.VDmed = median(VDall,4);
aux = prctile(VDall,[pctg_inf pctg_sup],4);
SRout.VDinf = aux(:,:,:,1);
SRout.VDsup = aux(:,:,:,2);

% Compute IR, VD, and HD based on the VARdraw that is closest to the median
% B matrix
VARopt.ident = 'sr';
label = {['draw' num2str(sel)]};  % Recover the position in VARdraw
VAR = VAR_draw.(label{1});        % Set a VAR based on the selected VARdraw
SRout.IR = VARir(VAR,VARopt);     % Compute IR
SRout.VD = VARvd(VAR,VARopt);     % Compute VD       
SRout.HD = VARhd(VAR,VARopt);     % Compute HD

