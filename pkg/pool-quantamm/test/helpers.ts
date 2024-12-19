import math = require("mathjs");

export function calculateGradient(
  points: Array<Array<number>>,
  lambda: number[]
) {
  const res = [new Array(points[0].length).fill(0)];
  const movingAverage = [...points[0]];
  const at = [];
  const bt = [];
  const numCoordinates = points[0].length;
  for (let j = 0; j < numCoordinates; j++) {
    at.push(0);
    bt.push(0);
  }
  for (let i = 1; i < points.length; i++) {
    const point = points[i];
    for (let j = 0; j < numCoordinates; j++) {
      let lambdaIndex = j;
      if (lambda.length == 1) {
        lambdaIndex = 0;
      }
      movingAverage[j] +=
        (1 - lambda[lambdaIndex]) * (point[j] - movingAverage[j]);
      at[j] =
        lambda[lambdaIndex] * at[j] +
        (point[j] - movingAverage[j]) / (1 - lambda[lambdaIndex]);
      bt[j] =
        (Math.pow(1 - lambda[lambdaIndex], 3) / lambda[lambdaIndex]) * at[j];
    }
    res.push([...bt]);
  }
  return res;
}

export function calculateCovariances(
  points: Array<Array<number>>,
  lambda: number
) {
  const numCoordinates = points[0].length;
  const res = [];
  const firstEntry = [];
  for (let i = 0; i < numCoordinates; i++) {
    firstEntry.push(new Array(numCoordinates).fill(0));
  }
  res.push(firstEntry);
  const movingAverage = [...points[0]];
  let At: any = [];

  for (let j = 0; j < numCoordinates; j++) {
    At.push(new Array(numCoordinates).fill(0));
  }
  for (let i = 1; i < points.length; i++) {
    const point = points[i];
    const prevMovingAverage = [...movingAverage];
    for (let j = 0; j < numCoordinates; j++) {
      movingAverage[j] += (1 - lambda) * (point[j] - movingAverage[j]);
    }
    const outerProduct = math.multiply(
      math.transpose([math.subtract(point, prevMovingAverage)]),
      [math.subtract(point, movingAverage)]
    );
    At = math.add(math.multiply(lambda, At), outerProduct);
    res.push(math.multiply(1 - lambda, At));
  }
  return res;
}

export function calculateVariances(
  points: Array<Array<number>>,
  lambda: number
) {
  const variances: any = [];
  const covariances = calculateCovariances(points, lambda);
  const numDataPoints = points[0].length;
  for (let i = 0; i < points.length; i++) {
    const varianceVector: any = [];
    for (let j = 0; j < numDataPoints; j++) {
      varianceVector.push(covariances[i][j][j]);
    }
    variances.push(varianceVector);
  }
  return variances;
}

export function calculatePrecision(
  points: Array<Array<number>>,
  lambda: number
) {
  const numCoordinates = points[0].length;
  const res = [];
  const firstEntry = [];
  for (let i = 0; i < numCoordinates; i++) {
    firstEntry.push(new Array(numCoordinates).fill(1));
  }
  res.push(firstEntry);
  const movingAverage = [...points[0]];
  let St: any = [];

  for (let j = 0; j < numCoordinates; j++) {
    St.push(new Array(numCoordinates).fill(0));
  }
  for (let i = 1; i < points.length; i++) {
    const point = points[i];
    const prevMovingAverage = [...movingAverage];
    for (let j = 0; j < numCoordinates; j++) {
      movingAverage[j] += (1 - lambda) * (point[j] - movingAverage[j]);
    }
    const outerProduct = math.multiply(
      math.transpose([math.subtract(point, prevMovingAverage)]),
      [math.subtract(point, movingAverage)]
    );
    const denominator = math.add(lambda, math.multiply(outerProduct, St));
    const numerator = math.add(
      lambda,
      math.multiply(
        math.transpose(
          math.multiply([math.subtract(point, movingAverage)], St)
        ),
        [math.subtract(point, prevMovingAverage)]
      )
    );
    St = math.multiply(
      math.multiply(1 / lambda, St),
      math.subtract(
        math.identity(numCoordinates).toArray(),
        math.dotDivide(denominator, numerator)
      )
    );
    res.push(math.divide(St, 1 - lambda));
  }
  return res;
}
