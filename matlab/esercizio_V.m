clear all
clc
close all

%% File di input
file_eustx = 'EUSTX.xlsx';
file_vstoxx = 'VSTOXX.xlsx';

%% Lettura dati (Date, Price)
tabella_eustx = readtable(file_eustx);

opzioni_vstoxx = detectImportOptions(file_vstoxx);
opzioni_vstoxx.VariableNamesRange = 'A3';
opzioni_vstoxx.DataRange = 'A4';
opzioni_vstoxx.VariableNamingRule = 'preserve';
tabella_vstoxx = readtable(file_vstoxx, opzioni_vstoxx);

data_eustx = tabella_eustx{:,1};
prezzo_eustx = tabella_eustx{:,2};

data_vstoxx = tabella_vstoxx{:,1};
prezzo_vstoxx = tabella_vstoxx{:,2};

% Converto le date (qualora fosse necessario)
if ~isdatetime(data_eustx)
if isnumeric(data_eustx)
data_eustx = datetime(data_eustx,'ConvertFrom','excel');
else
data_eustx = datetime(data_eustx);
end
end

if ~isdatetime(data_vstoxx)
if isnumeric(data_vstoxx)
data_vstoxx = datetime(data_vstoxx,'ConvertFrom','excel');
else
data_vstoxx = datetime(data_vstoxx);
end
end

% Pulizia dei dati (tolgo NaN e le date che, eventualmente, non sono valide)
ok = ~isnat(data_eustx) & ~isnan(prezzo_eustx);
data_eustx = data_eustx(ok);
prezzo_eustx = prezzo_eustx(ok);

ok = ~isnat(data_vstoxx) & ~isnan(prezzo_vstoxx);
data_vstoxx = data_vstoxx(ok);
prezzo_vstoxx = prezzo_vstoxx(ok);

% Ordino per data
[data_eustx, idx] = sort(data_eustx);
prezzo_eustx = prezzo_eustx(idx);

[data_vstoxx, idx] = sort(data_vstoxx);
prezzo_vstoxx = prezzo_vstoxx(idx);

% Allineo alle date in comune
[data_comuni, ia, ib] = intersect(data_eustx, data_vstoxx);
prezzo_eustx = prezzo_eustx(ia);
prezzo_vstoxx = prezzo_vstoxx(ib);

%% Log-returns e correlazione (leverage effect)
rend_log_eustx = diff(log(prezzo_eustx));
rend_log_vstoxx = diff(log(prezzo_vstoxx));

[rho_mat, p_mat] = corrcoef(rend_log_eustx, rend_log_vstoxx);
correlazione = rho_mat(1,2);
pvalue = p_mat(1,2);

disp('Esercizio 5 (punto v) : scatterplot rendimenti e stima Vasicek (OLS)')
fprintf('Osservazioni (prezzi, date comuni): %d\n', length(data_comuni))
fprintf('Osservazioni (rendimenti): %d\n', length(rend_log_eustx))
fprintf('Correlazione tra log-returns (EUSTX, VSTOXX): %.4f  (p-value = %.4g)\n', correlazione, pvalue)

if correlazione < 0
disp('Leverage effect: coerente (correlazione negativa).')
else
disp('Leverage effect: non evidente (correlazione non negativa).')
end

figure(1)
clf
plot(rend_log_eustx, rend_log_vstoxx, 'o')
grid on
xlabel('Log-return EUROSTOXX50')
ylabel('Log-return VSTOXX')
title('Scatterplot dei log-returns (leverage effect)')

%% Vasicek (OLS) su log-returns EUROSTOXX50
passo_temporale = 1;

R = rend_log_eustx(:);
Y = R(2:end);
X = R(1:end-1);

offset = ones(length(X),1);
beta = [X, offset] \ Y;

a_eustx = beta(1);
b_eustx = beta(2);

lambda_eustx = (1 - a_eustx) / passo_temporale;
mu_eustx = b_eustx / (1 - a_eustx);

residui = Y - [X, offset]*beta;
sigma_eustx = sqrt(var(residui, 1) / passo_temporale);

fprintf('\nVasicek OLS su log-returns EUROSTOXX50\n')
fprintf('a = %.6f, b = %.6f\n', a_eustx, b_eustx)
fprintf('lambda = %.6f, mu = %.6f, sigma = %.6f\n', lambda_eustx, mu_eustx, sigma_eustx)

figure(2)
clf
plot(X, Y, '.')
lsline
grid on
xlabel('r_i (EUROSTOXX50)')
ylabel('r_{i+1} (EUROSTOXX50)')
title('OLS su EUROSTOXX50: r_{i+1} rispetto a r_i')

%% Vasicek (OLS) su log-returns VSTOXX
R = rend_log_vstoxx(:);
Y = R(2:end);
X = R(1:end-1);

offset = ones(length(X),1);
beta = [X, offset] \ Y;

a_vstoxx = beta(1);
b_vstoxx = beta(2);

lambda_vstoxx = (1 - a_vstoxx) / passo_temporale;
mu_vstoxx = b_vstoxx / (1 - a_vstoxx);

residui = Y - [X, offset]*beta;
sigma_vstoxx = sqrt(var(residui, 1) / passo_temporale);

fprintf('\nVasicek OLS su log-returns VSTOXX\n')
fprintf('a = %.6f, b = %.6f\n', a_vstoxx, b_vstoxx)
fprintf('lambda = %.6f, mu = %.6f, sigma = %.6f\n', lambda_vstoxx, mu_vstoxx, sigma_vstoxx)

figure(3)
clf
plot(X, Y, '.')
lsline
grid on
xlabel('r_i (VSTOXX)')
ylabel('r_{i+1} (VSTOXX)')
title('OLS su VSTOXX: r_{i+1} rispetto a r_i')